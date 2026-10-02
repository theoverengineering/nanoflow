import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import 'tail.dart';

/// The `runs` directory of one graph as far as the feed has given it.
///
/// Each [scan] goes through the tree once and gives what has appeared since
/// the scan before. Names that start with `.` are never looked at: the store
/// builds files and directories under such names and renames them into place
/// once they are complete.
///
/// What has ended is not looked at again: nothing is written to a run after
/// its last event (`run-split`, `run-finished`, `run-failed`), nor to a
/// session all of whose runs have ended. A run is read once more after the
/// scan that read its last event, and its session once more after that: the
/// scan may have listed the run's steps, or the session's runs, before the
/// engine put in place the last step or the runs its split made.
final class Scanner {
  Scanner({required this.runsDir, required this.graphName});

  final String runsDir;

  final String graphName;

  /// The sessions given, by directory.
  final Map<String, _Session> _sessions = {};

  /// The sessions, runs and steps given, by id.
  final Map<String, _Session> _sessionsById = {};
  final Map<String, _Run> _runsById = {};
  final Map<String, _Step> _stepsById = {};

  /// Paths whose problem has been given as an error: it is given once.
  final Set<String> _reported = {};

  /// Gives to [out] what has appeared since the scan before: for each session,
  /// newest first, `session-added` (once), then for each of its runs in name
  /// order `run-added` (once), its new steps, its journal's new complete lines
  /// and a `step-changed` for a step that got its `outputId`, then the
  /// session's new documents.
  ///
  /// Newest first: a feed of a long history gives first the sessions that
  /// are likely to be looked at.
  ///
  /// A file that is not there yet is looked for again by the next scan. A
  /// file or directory that cannot be read, or a file that is not its model,
  /// is given to [out] as an error, once, and is looked at again by the next
  /// scans too.
  Future<void> scan(EventSink<Change> out) async {
    final sessions = await _attempt(
      runsDir,
      out,
      () => builtDirs(runsDir, (name) => isSessionDirOf(name, graphName)),
    );
    for (final dir in (sessions ?? const <String>[]).reversed) {
      await _scanSession(dir, out);
    }
  }

  String? sessionPath(String sessionId) => _sessionsById[sessionId]?.dir;

  String? runPath(String runId) => _runsById[runId]?.dir;

  String? stepPath(String stepId) => _stepsById[stepId]?.dir;

  String? logPath(String stepId) {
    final step = _stepsById[stepId];
    final log = step?.step.log;
    return step == null || log == null ? null : p.join(step.dir, log);
  }

  String? documentPath(String sessionId, String documentId) {
    final session = _sessionsById[sessionId];
    return session == null || !session.documents.contains(documentId)
        ? null
        : p.join(session.dir, documentsDirName, documentFileName(documentId));
  }

  Future<void> _scanSession(String dir, EventSink<Change> out) async {
    var session = _sessions[dir];
    if (session != null && session.ended) return;
    if (session == null) {
      final model = await _readModel(
        p.join(dir, sessionFileName),
        Session.fromJson,
        out,
      );
      if (model == null) return;
      session = _sessions[dir] = _sessionsById[model.id] = _Session(model, dir);
      out.add(SessionAdded(model));
    }
    // Whether every run had ended before this scan listed them: then the
    // listing has every run their splits made.
    final known = session.runs;
    final runsEnded =
        known.isNotEmpty && known.values.every((run) => run.ended);
    final runs = await _attempt(dir, out, () => builtDirs(dir));
    final ended = runsEnded && runs != null && runs.every(known.containsKey);
    for (final runDir in runs ?? const <String>[]) {
      await _scanRun(session, runDir, out);
    }
    // A session written by hand may have no documents directory.
    final documentsDir = p.join(dir, documentsDirName);
    final documents = await _attempt(
      documentsDir,
      out,
      () => _documentIds(documentsDir),
    );
    for (final documentId in documents ?? const <String>[]) {
      if (session.documents.add(documentId)) {
        out.add(
          DocumentAdded(sessionId: session.session.id, documentId: documentId),
        );
      }
    }
    // Documents are written before the events that refer to them.
    session.ended = ended && documents != null;
  }

  Future<void> _scanRun(
    _Session session,
    String dir,
    EventSink<Change> out,
  ) async {
    var run = session.runs[dir];
    if (run != null && run.ended) return;
    if (run == null) {
      final model = await _readModel(
        p.join(dir, runFileName),
        Run.fromJson,
        out,
      );
      if (model == null) return;
      run = session.runs[dir] = _runsById[model.id] = _Run(model, dir);
      out.add(RunAdded(model));
    }
    // Whether its last event was read before this scan listed its steps:
    // then the listing has every step it has.
    final lastRead = run.lastRead;
    final stepsDir = p.join(dir, stepsDirName);
    final steps = await _attempt(stepsDir, out, () => builtDirs(stepsDir));
    for (final stepDir in steps ?? const <String>[]) {
      await _scanStep(run, stepDir, out);
    }
    final lines = await _attempt(run.journal.path, out, run.journal.readLines);
    for (final (:number, :bytes) in lines ?? const <Line>[]) {
      final change = _journalChange(run.run.id, number, bytes);
      switch (change) {
        case EventAdded(event: StepFinished(:final stepId, outputId: _?)):
          run.finishedWithOutput.add(stepId);
        case EventAdded(event: RunSplit() || RunFinished() || RunFailed()):
          run.lastRead = true;
        default:
      }
      out.add(change);
    }
    run.ended =
        lastRead &&
        steps != null &&
        steps.every(run.steps.containsKey) &&
        !run.awaitsAnyOutput;
  }

  /// Gives a step that is new, or a step given without `outputId` whose
  /// `step-finished` has one: its `step.json` is rewritten with the
  /// `outputId` after that event is written.
  Future<void> _scanStep(_Run run, String dir, EventSink<Change> out) async {
    final known = run.steps[dir];
    if (known != null && !run.awaitsOutput(known.step)) return;
    final step = await _readModel(
      p.join(dir, stepFileName),
      Step.fromJson,
      out,
    );
    if (step == null) return;
    if (known == null) {
      run.steps[dir] = _stepsById[step.id] = _Step(step, dir);
      out.add(StepAdded(step));
    } else if (step.outputId != null) {
      known.step = step;
      out.add(StepChanged(step));
    }
  }

  /// The model in the file at [path], or `null` when it is not there or
  /// cannot be read.
  Future<T?> _readModel<T>(
    String path,
    T Function(Map<String, Object?> json) fromJson,
    EventSink<Change> out,
  ) => _attempt(path, out, () => readModel(path, fromJson));

  /// What [read] of [path] gives, or `null` when [path] is not there, or
  /// when [read] fails, which is given to [out] as an error once for [path].
  Future<T?> _attempt<T>(
    String path,
    EventSink<Change> out,
    Future<T> Function() read,
  ) async {
    try {
      return await read();
    } on PathNotFoundException {
      return null;
    } on IOException catch (error, stack) {
      if (_reported.add(path)) out.addError(error, stack);
    } on FormatException catch (error, stack) {
      if (_reported.add(path)) out.addError(error, stack);
    }
    return null;
  }
}

/// The directories in [parent] that [accepts] by name, in name order: by
/// default those whose name ends with an id.
///
/// Throws a [PathNotFoundException] when there is no [parent].
Future<List<String>> builtDirs(
  String parent, [
  bool Function(String name) accepts = _endsWithId,
]) async => [
  for (final entity in await _visibleEntries(parent))
    if (entity is Directory && accepts(_name(entity))) entity.path,
]..sort();

/// Reads the model in the JSON file at [path] with [fromJson].
///
/// Throws a [FormatException] whose message starts with [path] when the file
/// is not a JSON object in UTF-8 or not the model's JSON form.
Future<T> readModel<T>(
  String path,
  T Function(Map<String, Object?> json) fromJson,
) async {
  final bytes = await File(path).readAsBytes();
  try {
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, Object?>) {
      throw const FormatException('expected a JSON object');
    }
    return fromJson(json);
  } on FormatException catch (e) {
    throw FormatException('$path: ${e.message}');
  }
}

/// The ids of the documents in the `documents` directory [dir], in name
/// order.
Future<List<String>> _documentIds(String dir) async => [
  for (final entity in await _visibleEntries(dir))
    if (entity is File)
      if (p.basenameWithoutExtension(entity.path) case final id
          when isId(id) && _name(entity) == documentFileName(id))
        id,
]..sort();

/// The entries of [dir] whose name does not start with `.`: the store builds
/// files and directories under such names.
Future<List<FileSystemEntity>> _visibleEntries(String dir) async => [
  for (final entity in await Directory(dir).list().toList())
    if (!_name(entity).startsWith('.')) entity,
];

/// The change a complete [line] of the journal of the run [runId] gives: an
/// event, or `log-corrupted` when the line is not a JSON object with string
/// `runId`, `time` and `event`. [number] counts lines from 1.
Change _journalChange(String runId, int number, Uint8List line) {
  if (_decode(line) case final Map<String, Object?> json
      when json['runId'] is String &&
          json['time'] is String &&
          json['event'] is String) {
    return EventAdded(Event.fromJson(json));
  }
  return LogCorrupted(
    runId: runId,
    line: number,
    text: utf8.decode(line, allowMalformed: true),
  );
}

/// The JSON value in [line], or `null` when it is not JSON in UTF-8.
Object? _decode(Uint8List line) {
  try {
    return jsonDecode(utf8.decode(line));
  } on FormatException {
    return null;
  }
}

String _name(FileSystemEntity entity) => p.basename(entity.path);

bool _endsWithId(String name) => idOfDirName(name) != null;

/// A session given, with what of it has been given.
final class _Session {
  _Session(this.session, this.dir);

  final Session session;

  final String dir;

  /// Its runs, by directory.
  final Map<String, _Run> runs = {};

  /// Ids of its documents.
  final Set<String> documents = {};

  /// Whether every run of it has ended, and it has been read since: nothing
  /// more is written to it.
  bool ended = false;
}

/// A run given, with what of it has been given.
final class _Run {
  _Run(this.run, this.dir) : journal = Tail(p.join(dir, eventsFileName));

  final Run run;

  final String dir;

  /// Its journal, read up to the end of the last complete line.
  final Tail journal;

  /// Its steps, by directory.
  final Map<String, _Step> steps = {};

  /// Ids of its steps whose `step-finished` has an `outputId`.
  final Set<String> finishedWithOutput = {};

  /// Whether its last event has been read.
  bool lastRead = false;

  /// Whether it has been read in full since its last event was: nothing
  /// more is written to it.
  bool ended = false;

  /// Whether [step] was given without the `outputId` its `step-finished`
  /// has: its `step.json` is rewritten with it.
  bool awaitsOutput(Step step) =>
      step.outputId == null && finishedWithOutput.contains(step.id);

  /// Whether a step of it [awaitsOutput].
  bool get awaitsAnyOutput =>
      steps.values.any((given) => awaitsOutput(given.step));
}

/// A step given, as it was last given.
final class _Step {
  _Step(this.step, this.dir);

  Step step;

  final String dir;
}
