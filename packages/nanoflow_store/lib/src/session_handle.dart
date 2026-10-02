import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import 'atomic.dart';
import 'owner_lock.dart';

const _newline = 0x0a;

/// One session on disk: what the process that runs it writes, and what it
/// reads back to continue it after a crash.
///
/// Only one process works with a session at a time: the handle holds the
/// session's lock until [release] or the end of the process.
final class SessionHandle {
  SessionHandle._(this.session, this.dir, this._clock, this._lock)
    : _stepTimes = _IncreasingTimes();

  /// [from] after its directory was renamed to [dir]. The times it has given
  /// its steps stay taken, and it keeps its lock.
  SessionHandle._moved(SessionHandle from, this.dir)
    : session = from.session,
      _clock = from._clock,
      _lock = from._lock,
      _stepTimes = from._stepTimes;

  /// The session's fields, as in `session.json`.
  final Session session;

  /// The session's directory.
  final String dir;

  final Clock _clock;

  /// The open lock file that keeps other processes off the session; `null`
  /// once released.
  RandomAccessFile? _lock;

  /// Times of the session's steps: a step directory's name must sort after
  /// those of the steps created before it.
  final _IncreasingTimes _stepTimes;

  /// Directories of the steps looked up so far, by id. A directory keeps its
  /// name once it is built.
  final Map<String, String> _stepDirs = {};

  String get _stepsDir => p.join(dir, stepsDirName);

  /// The events of the session, in the order they were written.
  ///
  /// An incomplete last line, one that is still being written, is left out.
  /// Throws a [StoreCorruptedException] for a complete line that is not a JSON
  /// object; an object that is not an event this version knows is an
  /// [UnknownEvent].
  Future<List<Event>> events() => readJournal(p.join(dir, eventsFileName));

  /// The records of the session's steps, ordered by directory name: in the
  /// order they were created.
  Future<List<Step>> steps() async => [
    for (final step in _builtDirs(_stepsDir))
      await readModel(p.join(step.path, stepFileName), Step.fromJson),
  ];

  /// The value of the document [documentId].
  Future<Object?> documentValue(String documentId) async => (await readModel(
    p.join(dir, documentsDirName, documentFileName(documentId)),
    Document.fromJson,
  )).value;

  /// Creates the record of a step: `steps/<time>-<name>-<id>/step.json`,
  /// without `outputId`. No event is written.
  ///
  /// The step's directory appears whole, with `step.json`. Its name holds the
  /// time from the clock, but at least a millisecond after the time of the
  /// step created before it, so that steps sort by name in the order they
  /// were created.
  ///
  /// Throws a [FileSystemException], having built nothing, when the
  /// session's directory is gone.
  Future<Step> createStep({
    required String name,
    required String key,
    required String? after,
    required String? place,
  }) async {
    final step = Step(
      id: newId(),
      sessionId: session.id,
      name: name,
      key: key,
      after: after,
      place: place,
      outputId: null,
      log: logFileName,
    );
    // Kept, so that a step whose directory is removed later is not looked up
    // again, which would find it missing rather than fail as a write into it
    // does.
    _stepDirs[step.id] = await buildDirAtomically(
      _stepsDir,
      id: step.id,
      name: stepDirName(_stepTimes.next(_clock), name, step.id),
      build: (dir) =>
          writeJsonAtomically(p.join(dir, stepFileName), step.toJson()),
    );
    return step;
  }

  /// Appends [event] to the session's journal: one line, flushed.
  ///
  /// Throws a [PathNotFoundException] when the session has no journal, which
  /// is not made again; and, once the line is written, when the session has
  /// no `session.json`. Either way the session is gone or being removed, as
  /// by `rm -rf`, which removes it depth first while the process still
  /// writes to what it has not reached yet: the process learns of it within
  /// one event.
  Future<void> appendEvent(KnownEvent event) async {
    await _appendToJournal(p.join(dir, eventsFileName), event);
    final sessionFile = p.join(dir, sessionFileName);
    if (!await File(sessionFile).exists()) {
      throw _missing('Cannot find file', sessionFile);
    }
  }

  /// Writes a new document holding [value]; returns its id.
  Future<String> writeDocument(Object? value) =>
      writeDocumentAt(dir, session.id, value);

  /// Rewrites `step.json` of [step] with [outputId]; returns the step as it is
  /// now.
  Future<Step> setStepOutput(Step step, String outputId) async {
    final changed = step.withOutput(outputId);
    await writeJsonAtomically(
      p.join(_stepDir(step.id), stepFileName),
      changed.toJson(),
    );
    return changed;
  }

  /// Opens the log of the step [stepId] for appending: a step that runs
  /// again adds to the log it has.
  ///
  /// The log throws no error of its file: [StepLog.failed] gives it.
  StepLog openLog(String stepId) =>
      StepLog._(File(p.join(_stepDir(stepId), logFileName)));

  /// Gives up the session's lock: another process may own the session from
  /// now on. Reading through the handle still works; writing through it must
  /// not be done any more.
  Future<void> release() async {
    final lock = _lock;
    _lock = null;
    await lock?.close();
  }

  String _stepDir(String stepId) => _stepDirs[stepId] ??=
      _builtDirOf(_stepsDir, stepId) ??
      (throw ArgumentError.value(
        stepId,
        'stepId',
        'no such step in session ${session.id}',
      ));
}

/// The log of one step, open for appending.
///
/// Its file is written in the background, in the order the bytes were added:
/// what is added while a write is under way waits, and goes in one write
/// after it, so the writes keep up with bytes that come in many small
/// chunks. [unwritten] tells how much waits. No error of the file is thrown,
/// now or later: when the file cannot be opened, written or closed — its
/// directory is gone, the disk is full — [failed] completes with why, and
/// the log writes nothing more.
final class StepLog {
  StepLog._(File file) {
    _writing = _guarded(() async {
      _file = await file.open(mode: FileMode.append);
    });
  }

  RandomAccessFile? _file;

  /// The open, then each write, one after another: completes after the
  /// last.
  late Future<void> _writing;

  /// What was added and is not being written yet.
  final _waiting = BytesBuilder(copy: false);

  /// Whether a write of [_waiting] is to come.
  bool _writeScheduled = false;

  int _unwritten = 0;

  final _failed = Completer<FileSystemException>();

  bool _closed = false;

  /// Completes with the error of the first open, write or close of the file
  /// that failed.
  Future<FileSystemException> get failed => _failed.future;

  /// How many of the bytes added so far are not written yet: 0 once the log
  /// has failed, as it drops them.
  int get unwritten => _unwritten;

  /// Adds [bytes] to the end of the log. They are not copied: [bytes] must
  /// not change afterwards.
  void add(List<int> bytes) {
    if (_closed) throw StateError('the log is closed');
    if (_failed.isCompleted || bytes.isEmpty) return;
    _waiting.add(bytes);
    _unwritten += bytes.length;
    if (_writeScheduled) return;
    _writeScheduled = true;
    _writing = _writing.then((_) => _writeWaiting());
  }

  /// Writes what waits, in one write, until nothing does.
  Future<void> _writeWaiting() async {
    while (_waiting.isNotEmpty && !_failed.isCompleted) {
      final bytes = _waiting.takeBytes();
      await _guarded(() => _file!.writeFrom(bytes));
      _unwritten -= bytes.length;
    }
    if (_failed.isCompleted) {
      _waiting.clear();
      _unwritten = 0;
    }
    _writeScheduled = false;
  }

  /// Completes once everything added so far is written to the file, or the
  /// log has failed.
  Future<void> flush() => _writing;

  /// Writes what is left and closes the log.
  Future<void> close() {
    if (!_closed) {
      _closed = true;
      _writing = _writing.then((_) {
        final file = _file;
        _file = null;
        return file == null ? null : _guarded(file.close);
      });
    }
    return _writing;
  }

  /// Runs [io], an operation on the file; when it fails, [failed] gives why.
  Future<void> _guarded(Future<void> Function() io) async {
    try {
      await io();
    } on FileSystemException catch (e) {
      if (!_failed.isCompleted) _failed.complete(e);
    }
  }
}

/// A journal has a complete line that is not a JSON object.
final class StoreCorruptedException implements Exception {
  const StoreCorruptedException({required this.path, required this.line});

  /// The journal's path.
  final String path;

  /// The number of the line, from 1.
  final int line;

  @override
  String toString() =>
      'StoreCorruptedException: line $line of $path is not a JSON object';
}

/// A handle of the session [session] in [dir], for the store that is building
/// it and holds its [lock]. Not exported.
SessionHandle sessionHandleAt(
  String dir,
  Session session,
  Clock clock,
  RandomAccessFile lock,
) => SessionHandle._(session, dir, clock, lock);

/// [handle] once its session's directory has been renamed to [dir], for the
/// store that has built it. Not exported.
SessionHandle movedSessionHandle(SessionHandle handle, String dir) =>
    SessionHandle._moved(handle, dir);

/// A handle of the session [sessionId] in [dir], for the store that is
/// opening it.
///
/// Takes the session's lock first: throws a [SessionBusyException] when
/// another process holds it, and changes nothing. Then cuts an incomplete
/// last line off the journal: the process that owned the session died while
/// writing it, and the next event must start on a line of its own. Not
/// exported.
Future<SessionHandle> loadSessionHandle(
  String dir,
  String sessionId,
  Clock clock,
) async {
  final lock = await lockSession(dir, sessionId);
  try {
    final session = await readModel(
      p.join(dir, sessionFileName),
      Session.fromJson,
    );
    await _cutIncompleteLine(p.join(dir, eventsFileName));
    return SessionHandle._(session, dir, clock, lock);
  } catch (_) {
    await lock.close();
    rethrow;
  }
}

/// Writes a new document of the session [sessionId] in its directory [dir],
/// holding [value]; returns its id. Not exported.
Future<String> writeDocumentAt(
  String dir,
  String sessionId,
  Object? value,
) async {
  final document = Document(id: newId(), sessionId: sessionId, value: value);
  await writeJsonAtomically(
    p.join(dir, documentsDirName, documentFileName(document.id)),
    document.toJson(),
  );
  return document.id;
}

/// Writes a new journal at [path] whose first line is [event], flushed. Not
/// exported.
Future<void> startJournal(String path, KnownEvent event) =>
    File(path).writeAsString(_line(event), flush: true);

/// The events of the journal at [path], in the order they were written. Not
/// exported.
///
/// An incomplete last line is left out. Throws a [StoreCorruptedException]
/// for a complete line that is not a JSON object.
Future<List<Event>> readJournal(String path) async {
  final bytes = await File(path).readAsBytes();
  final events = <Event>[];
  var start = 0;
  var end = bytes.indexOf(_newline);
  while (end != -1) {
    final event = _parseLine(bytes.sublist(start, end));
    if (event == null) {
      throw StoreCorruptedException(path: path, line: events.length + 1);
    }
    events.add(event);
    start = end + 1;
    end = bytes.indexOf(_newline, start);
  }
  return events;
}

/// Reads the JSON file at [path] with [fromJson]. Not exported.
///
/// Throws a [FormatException] that starts with [path] when the file is not a
/// JSON object or not the model's JSON form.
Future<T> readModel<T>(
  String path,
  T Function(Map<String, Object?> json) fromJson,
) async {
  final text = await File(path).readAsString();
  try {
    final json = jsonDecode(text);
    if (json is! Map<String, Object?>) {
      throw const FormatException('expected a JSON object');
    }
    return fromJson(json);
  } on FormatException catch (e) {
    throw FormatException('$path: ${e.message}');
  }
}

/// Times from a clock, to the millisecond, each at least a millisecond after
/// the one before: names that hold them sort in the order they were taken,
/// even when the clock has not moved on or has gone back.
final class _IncreasingTimes {
  int? _last;

  DateTime next(Clock clock) {
    final now = clock().millisecondsSinceEpoch;
    final last = _last;
    final time = last == null || now > last ? now : last + 1;
    _last = time;
    return DateTime.fromMillisecondsSinceEpoch(time, isUtc: true);
  }
}

/// The built directories in [parent], ordered by name.
List<({String id, String path})> _builtDirs(String parent) => [
  for (final entity in Directory(parent).listSync())
    if (idOfBuiltDir(entity) case final id?) (id: id, path: entity.path),
]..sort((a, b) => a.path.compareTo(b.path));

/// The built directory in [parent] whose id is [id], or `null`.
String? _builtDirOf(String parent, String id) {
  for (final dir in _builtDirs(parent)) {
    if (dir.id == id) return dir.path;
  }
  return null;
}

/// The event on a journal [line] without its `\n`, or `null` when the line is
/// not a JSON object.
Event? _parseLine(List<int> line) {
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(line));
  } on FormatException {
    return null;
  }
  return json is Map<String, Object?> ? Event.fromJson(json) : null;
}

/// [event] as a line of a journal: compact JSON and `\n`.
String _line(KnownEvent event) => '${jsonEncode(event.toJson())}\n';

/// Appends [event] to the journal at [path] as one line, flushed.
///
/// Throws a [PathNotFoundException] when there is no journal at [path].
/// Opening a file to append to makes it when it is missing; a journal is
/// never empty, so an empty one is one this made, and it is removed again.
Future<void> _appendToJournal(String path, KnownEvent event) async {
  final journal = await File(path).open(mode: FileMode.append);
  try {
    if (await journal.length() == 0) {
      try {
        await File(path).delete();
      } on FileSystemException {
        // Removed already, as the rest of the session is being.
      }
      throw _missing('Cannot open file', path);
    }
    await journal.writeString(_line(event));
    await journal.flush();
  } finally {
    await journal.close();
  }
}

/// The error of a file at [path] that is missing, as an operation of
/// [message] would have thrown it.
PathNotFoundException _missing(String message, String path) =>
    PathNotFoundException(
      path,
      const OSError('No such file or directory', 2),
      message,
    );

/// Truncates the file at [path] after its last `\n`.
Future<void> _cutIncompleteLine(String path) async {
  final file = File(path);
  final bytes = await file.readAsBytes();
  final complete = bytes.lastIndexOf(_newline) + 1;
  if (complete == bytes.length) return;
  final open = await file.open(mode: FileMode.append);
  try {
    await open.truncate(complete);
  } finally {
    await open.close();
  }
}
