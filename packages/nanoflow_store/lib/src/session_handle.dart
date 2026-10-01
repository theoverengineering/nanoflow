import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import 'atomic.dart';

const _newline = 0x0a;

/// One session on disk: what the engine writes while it drives the session,
/// and what it reads back to continue it after a crash (`--resume`).
///
/// Only one engine process works with a session at a time.
final class SessionHandle {
  SessionHandle._(this.session, this.dir, this._clock)
    : _runTimes = _IncreasingTimes(),
      _stepTimes = {};

  /// [from] after its directory was renamed to [dir]. The times it has given
  /// its runs and steps stay taken.
  SessionHandle._moved(SessionHandle from, this.dir)
    : session = from.session,
      _clock = from._clock,
      _runTimes = from._runTimes,
      _stepTimes = from._stepTimes;

  /// The session's fields, as in `session.json`.
  final Session session;

  /// The session's directory.
  final String dir;

  final Clock _clock;

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
  Future<(Run, Step)> createRun({
    required String? parentId,
    required String node,
    required String? inputId,
  }) async {
    final run = Run(id: newId(), sessionId: session.id, parentId: parentId);
    final createdAt = _runTimes.next(_clock);
    late final Step step;
    _runDirs[run.id] = await buildDirAtomically(
      dir,
      id: run.id,
      name: runDirName(createdAt, run.id),
      build: (runDir) async {
        await writeJsonAtomically(p.join(runDir, runFileName), run.toJson());
        await _appendLine(
          p.join(runDir, eventsFileName),
          RunStarted(runId: run.id, time: createdAt, node: node),
        );
        step = await _buildStep(
          p.join(runDir, stepsDirName),
          runId: run.id,
          node: node,
          inputId: inputId,
        );
      },
    );
    return (run, step);
  }

  /// Creates a step of the run [runId] at [node], whose input is [inputId].
  ///
  /// The step's directory appears whole, with `step.json`. Its name holds the
  /// time from the clock, but at least a millisecond after the time of the
  /// run's step created before it, so that steps sort by name in the order
  /// they were created. No event is written.
  Future<Step> createStep({
    required String runId,
    required String node,
    required String? inputId,
  }) async => _buildStep(
    p.join(_runDir(runId), stepsDirName),
    runId: runId,
    node: node,
    inputId: inputId,
  );

  /// Appends [event] to the journal of its run: one line, flushed.
  Future<void> appendEvent(Event event) async {
    final runId = switch (event) {
      KnownEvent(:final runId) => runId,
      UnknownEvent(:final runId) =>
        runId ?? (throw ArgumentError.value(event, 'event', 'has no runId')),
    };
    await _appendLine(p.join(_runDir(runId), eventsFileName), event);
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

  /// Opens the command log of the step [stepId] of the run [runId] for
  /// appending: a step that runs again adds to the log it has.
  StepLog openLog(String runId, String stepId) => StepLog._(
    File(p.join(_stepDir(runId, stepId), logFileName))
        .openWrite(mode: FileMode.append),
  );

  /// Builds the directory of a new step in [stepsDir].
  Future<Step> _buildStep(
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
    await buildDirAtomically(
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
    return step;
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
final class StepLog {
  StepLog._(this._sink);

  final IOSink _sink;

  /// Adds [bytes] to the end of the log.
  void add(List<int> bytes) => _sink.add(bytes);

  /// Completes once everything added so far is written to the file.
  Future<void> flush() => _sink.flush();

  /// Writes what is left and closes the log.
  Future<void> close() => _sink.close();
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
/// it. Not exported.
SessionHandle sessionHandleAt(String dir, Session session, Clock clock) =>
    SessionHandle._(session, dir, clock);

/// [handle] once its session's directory has been renamed to [dir], for the
/// store that has built it. Not exported.
SessionHandle movedSessionHandle(SessionHandle handle, String dir) =>
    SessionHandle._moved(handle, dir);

/// A handle of the session in [dir], for the store that is opening it.
///
/// Cuts an incomplete last line off the journal of each run: the engine died
/// while writing it, and the next event must start on a line of its own. Not
/// exported.
Future<SessionHandle> loadSessionHandle(String dir, Clock clock) async {
  final session = await _readModel(
    p.join(dir, sessionFileName),
    Session.fromJson,
  );
  for (final run in _builtDirs(dir)) {
    await _cutIncompleteLine(p.join(run.path, eventsFileName));
  }
  return SessionHandle._(session, dir, clock);
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

/// Appends [event] to the journal at [path] as one compact line.
Future<void> _appendLine(String path, Event event) => File(path).writeAsString(
  '${jsonEncode(event.toJson())}\n',
  mode: FileMode.append,
  flush: true,
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
