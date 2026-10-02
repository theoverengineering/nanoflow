import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import 'atomic.dart';
import 'engine_lock.dart';

const _newline = 0x0a;

/// One session on disk: what the engine writes while it drives the session,
/// and what it reads back to continue it after a crash (`--resume`).
///
/// Only one engine process works with a session at a time: the handle holds
/// the session's lock until [release] or the end of the process.
final class SessionHandle {
  SessionHandle._(this.session, this.dir, this._clock, this._lock)
    : _runTimes = _IncreasingTimes(),
      _stepTimes = {};

  /// [from] after its directory was renamed to [dir]. The times it has given
  /// its runs and steps stay taken, and it keeps its lock.
  SessionHandle._moved(SessionHandle from, this.dir)
    : session = from.session,
      _clock = from._clock,
      _lock = from._lock,
      _runTimes = from._runTimes,
      _stepTimes = from._stepTimes;

  /// The session's fields, as in `session.json`.
  final Session session;

  /// The session's directory.
  final String dir;

  final Clock _clock;

  /// The open lock file that keeps other engine processes off the session;
  /// `null` once released.
  RandomAccessFile? _lock;

  /// Times of the session's runs, and of each run's steps by run id: a
  /// directory's name must sort after its siblings created before it.
  final _IncreasingTimes _runTimes;
  final Map<String, _IncreasingTimes> _stepTimes;

  /// Directories of the runs and steps looked up so far, by id. A directory
  /// keeps its name once it is built.
  final Map<String, String> _runDirs = {};
  final Map<String, String> _stepDirs = {};

  /// The session's runs, ordered by directory name: in the order they were
  /// created.
  Future<List<Run>> runs() async => [
    for (final run in _builtDirs(dir))
      await _readModel(p.join(run.path, runFileName), Run.fromJson),
  ];

  /// The events of the run [runId], in the order they were written.
  ///
  /// An incomplete last line, one that is still being written, is left out.
  /// Throws a [StoreCorruptedException] for a complete line that is not a JSON
  /// object; an object that is not an event this version knows is an
  /// [UnknownEvent].
  Future<List<Event>> events(String runId) async {
    final path = p.join(_runDir(runId), eventsFileName);
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

  /// The steps of the run [runId], ordered by directory name: in the order
  /// they were created.
  Future<List<Step>> steps(String runId) async => [
    for (final step in _builtDirs(p.join(_runDir(runId), stepsDirName)))
      await _readModel(p.join(step.path, stepFileName), Step.fromJson),
  ];

  /// The value of the document [documentId].
  Future<Object?> documentValue(String documentId) async => (await _readModel(
    p.join(dir, documentsDirName, documentFileName(documentId)),
    Document.fromJson,
  )).value;

  /// Creates a run of the session together with its first step, at [node],
  /// whose input is [inputId]. The run's journal holds `run-started`.
  ///
  /// The run appears whole: its directory, `run.json`, `log.jsonl` and the
  /// step's directory are built under a temporary name and renamed into place.
  /// The run's time, in its directory's name and in `run-started`, comes from
  /// the clock, but is at least a millisecond after the time of the run
  /// created before it, so that runs sort by name in the order they were
  /// created. The step's directory is named the same way.
  ///
  /// Throws a [FileSystemException], having built nothing, when the
  /// session's directory is gone.
  Future<(Run, Step)> createRun({
    required String? parentId,
    required String node,
    required String? inputId,
  }) async {
    final run = Run(id: newId(), sessionId: session.id, parentId: parentId);
    final createdAt = _runTimes.next(_clock);
    late final Step step;
    late final String stepName;
    final runDir = _runDirs[run.id] = await buildDirAtomically(
      dir,
      id: run.id,
      name: runDirName(createdAt, run.id),
      build: (runDir) async {
        await writeJsonAtomically(p.join(runDir, runFileName), run.toJson());
        await _startJournal(
          p.join(runDir, eventsFileName),
          RunStarted(runId: run.id, time: createdAt, node: node),
        );
        final stepsDir = await Directory(p.join(runDir, stepsDirName)).create();
        final built = await _buildStep(
          stepsDir.path,
          runId: run.id,
          node: node,
          inputId: inputId,
        );
        step = built.step;
        stepName = p.basename(built.dir);
      },
    );
    _stepDirs[step.id] = p.join(runDir, stepsDirName, stepName);
    return (run, step);
  }

  /// Creates a step of the run [runId] at [node], whose input is [inputId].
  ///
  /// The step's directory appears whole, with `step.json`. Its name holds the
  /// time from the clock, but at least a millisecond after the time of the
  /// run's step created before it, so that steps sort by name in the order
  /// they were created. No event is written.
  ///
  /// Throws a [FileSystemException], having built nothing, when the run's
  /// directory is gone.
  Future<Step> createStep({
    required String runId,
    required String node,
    required String? inputId,
  }) async {
    final (:step, :dir) = await _buildStep(
      p.join(_runDir(runId), stepsDirName),
      runId: runId,
      node: node,
      inputId: inputId,
    );
    _stepDirs[step.id] = dir;
    return step;
  }

  /// Appends [event] to the journal of its run: one line, flushed.
  ///
  /// Throws a [PathNotFoundException] when the run has no journal, which is
  /// not made again; and, once the line is written, when the session has no
  /// `session.json` or the run no `run.json`. Either way the session is gone
  /// or being removed, as by `rm -rf`, which removes it depth first while
  /// the engine still writes to what it has not reached yet: the engine
  /// learns of it within one event.
  Future<void> appendEvent(Event event) async {
    final runId = switch (event) {
      KnownEvent(:final runId) => runId,
      UnknownEvent(:final runId) =>
        runId ?? (throw ArgumentError.value(event, 'event', 'has no runId')),
    };
    final runDir = _runDir(runId);
    await _appendToJournal(p.join(runDir, eventsFileName), event);
    for (final path in [
      p.join(dir, sessionFileName),
      p.join(runDir, runFileName),
    ]) {
      if (!await File(path).exists()) throw _missing('Cannot find file', path);
    }
  }

  /// Writes a new document holding [value]; returns its id.
  Future<String> writeDocument(Object? value) async {
    final document = Document(id: newId(), sessionId: session.id, value: value);
    await writeJsonAtomically(
      p.join(dir, documentsDirName, documentFileName(document.id)),
      document.toJson(),
    );
    return document.id;
  }

  /// Rewrites `step.json` of [step] with [outputId]; returns the step as it is
  /// now.
  Future<Step> setStepOutput(Step step, String outputId) async {
    final changed = step.withOutput(outputId);
    await writeJsonAtomically(
      p.join(_stepDir(step.runId, step.id), stepFileName),
      changed.toJson(),
    );
    return changed;
  }

  /// Gives up the session's lock: another engine process may drive the
  /// session from now on. Reading through the handle still works; writing
  /// through it must not be done any more.
  Future<void> release() async {
    final lock = _lock;
    _lock = null;
    await lock?.close();
  }

  /// Opens the command log of the step [stepId] of the run [runId] for
  /// appending: a step that runs again adds to the log it has.
  ///
  /// The log throws no error of its file: [StepLog.failed] gives it.
  StepLog openLog(String runId, String stepId) =>
      StepLog._(File(p.join(_stepDir(runId, stepId), logFileName)));

  /// Builds the directory of a new step in [stepsDir]; gives the step and
  /// its directory.
  ///
  /// The callers keep the directory, as [createRun] keeps a run's: a step
  /// whose directory is removed later is not looked up again, which would
  /// find it missing rather than fail as a write into it does.
  Future<({Step step, String dir})> _buildStep(
    String stepsDir, {
    required String runId,
    required String node,
    required String? inputId,
  }) async {
    final step = Step(
      id: newId(),
      runId: runId,
      inputId: inputId,
      outputId: null,
      log: logFileName,
    );
    final dir = await buildDirAtomically(
      stepsDir,
      id: step.id,
      name: stepDirName(
        _stepTimes.putIfAbsent(runId, _IncreasingTimes.new).next(_clock),
        node,
        step.id,
      ),
      build: (dir) =>
          writeJsonAtomically(p.join(dir, stepFileName), step.toJson()),
    );
    return (step: step, dir: dir);
  }

  String _runDir(String runId) => _runDirs[runId] ??=
      _builtDirOf(dir, runId) ??
      (throw ArgumentError.value(
        runId,
        'runId',
        'no such run in session ${session.id}',
      ));

  String _stepDir(String runId, String stepId) => _stepDirs[stepId] ??=
      _builtDirOf(p.join(_runDir(runId), stepsDirName), stepId) ??
      (throw ArgumentError.value(
        stepId,
        'stepId',
        'no such step in run $runId',
      ));
}

/// The log of one step's command, open for appending.
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
/// another engine process holds it, and changes nothing. Then cuts an
/// incomplete last line off the journal of each run: the engine died while
/// writing it, and the next event must start on a line of its own. Not
/// exported.
Future<SessionHandle> loadSessionHandle(
  String dir,
  String sessionId,
  Clock clock,
) async {
  final lock = await lockSession(dir, sessionId);
  try {
    final session = await _readModel(
      p.join(dir, sessionFileName),
      Session.fromJson,
    );
    for (final run in _builtDirs(dir)) {
      await _cutIncompleteLine(p.join(run.path, eventsFileName));
    }
    return SessionHandle._(session, dir, clock, lock);
  } catch (_) {
    await lock.close();
    rethrow;
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

/// Reads the JSON file at [path] with [fromJson].
///
/// Throws a [FormatException] that starts with [path] when the file is not a
/// JSON object or not the model's JSON form.
Future<T> _readModel<T>(
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
String _line(Event event) => '${jsonEncode(event.toJson())}\n';

/// Writes a new journal at [path] whose first line is [event], flushed.
Future<void> _startJournal(String path, Event event) =>
    File(path).writeAsString(_line(event), flush: true);

/// Appends [event] to the journal at [path] as one line, flushed.
///
/// Throws a [PathNotFoundException] when there is no journal at [path].
/// Opening a file to append to makes it when it is missing; a journal is
/// never empty, so an empty one is one this made, and it is removed again.
Future<void> _appendToJournal(String path, Event event) async {
  final journal = await File(path).open(mode: FileMode.append);
  try {
    if (await journal.length() == 0) {
      try {
        await File(path).delete();
      } on FileSystemException {
        // Removed already, as the rest of the run is being.
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
