import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import 'owners.dart';
import 'tail.dart';

/// The sessions of a `runs` directory as far as the feed has given them.
///
/// Each [scan] goes through the tree once and gives what has appeared since
/// the scan before. Names that start with `.` are never looked at: the store
/// builds files and directories under such names and renames them into place
/// once they are complete.
///
/// What has ended is not looked at again: nothing is written to a session
/// after its last event (`session-finished`, `session-failed`). A session is
/// read once more after the scan that read its last event: that scan may
/// have listed the session's steps before the last of them was put in place.
///
/// The owner of a session whose journal goes on is read in every scan, after
/// the journal, and told by [owners].
final class Scanner {
  Scanner({required this.runsDir, required this.owners});

  final String runsDir;

  final Owners owners;

  /// The sessions given, by directory.
  final Map<String, _Session> _sessions = {};

  /// The sessions and steps given, by id.
  final Map<String, _Session> _sessionsById = {};
  final Map<String, _Step> _stepsById = {};

  /// Paths whose problem has been given as an error: it is given once.
  final Set<String> _reported = {};

  /// Gives to [out] what has appeared since the scan before: for each
  /// session, newest first, `session-added` (once), then its new steps and a
  /// `step-changed` for a step whose `step.json` was rewritten — with the
  /// `outputId` of its `step-finished`, or with another `after` when it runs
  /// again — its journal's new complete lines, then its new documents, then,
  /// while its journal goes on, `owner-changed` when its owner or whether it
  /// is alive has changed (see [Owners.update]).
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
      () => builtDirs(runsDir, isSessionDirName),
    );
    final newestFirst = [...?sessions]
      ..sort((a, b) {
        final byTime = _createdStamp(b).compareTo(_createdStamp(a));
        return byTime != 0 ? byTime : b.compareTo(a);
      });
    for (final dir in newestFirst) {
      await _scanSession(dir, out);
    }
  }

  String? sessionPath(String sessionId) => _sessionsById[sessionId]?.dir;

  String? stepPath(String stepId) => _stepsById[stepId]?.dir;

  String? logPath(String stepId) {
    final step = _stepsById[stepId];
    return step == null ? null : p.join(step.dir, step.step.log);
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
    final sessionId = session.session.id;
    // Whether its last event was read before this scan listed its steps:
    // then the listing has every step it has.
    final lastRead = session.lastRead;
    final stepsDir = p.join(dir, stepsDirName);
    final steps = await _attempt(stepsDir, out, () => builtDirs(stepsDir));
    for (final stepDir in steps ?? const <String>[]) {
      await _scanStep(session, stepDir, out);
    }
    // Taken before the journal is read: an owner's process that has exited
    // by now wrote all it did, and the journal read next has it.
    final fate = owners.fateOf(sessionId);
    final journal = session.journal;
    final lines = await _attempt(journal.path, out, journal.readLines);
    for (final (:number, :bytes) in lines ?? const <Line>[]) {
      final change = _journalChange(sessionId, number, bytes);
      switch (change) {
        case EventAdded(event: StepStarted(:final stepId)):
          session.stepStarted(stepId);
        case EventAdded(event: StepFinished(:final stepId, :final outputId)):
          session.stepEnded(stepId, outputId);
        case EventAdded(event: StepFailed(:final stepId)):
          session.stepEnded(stepId, null);
        case EventAdded(event: SessionFinished() || SessionFailed()):
          session.lastRead = true;
        default:
      }
      out.add(change);
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
        out.add(DocumentAdded(sessionId: sessionId, documentId: documentId));
      }
    }
    if (session.lastRead) {
      owners.drop(sessionId);
    } else {
      final lockFile = p.join(dir, ownerLockFileName);
      await _attempt(
        lockFile,
        out,
        () => owners.update(sessionId, lockFile, fate, out),
      );
    }
    session.ended =
        lastRead &&
        steps != null &&
        steps.every(session.steps.containsKey) &&
        !session.steps.values.any(session.mayChange) &&
        documents != null;
  }

  /// Gives a step that is new, or a step given before whose `step.json` may
  /// have been rewritten since (see [_Session.mayChange]) when it has been.
  Future<void> _scanStep(
    _Session session,
    String dir,
    EventSink<Change> out,
  ) async {
    final known = session.steps[dir];
    if (known != null && !session.mayChange(known)) return;
    final step = await _readModel(
      p.join(dir, stepFileName),
      Step.fromJson,
      out,
    );
    if (step == null) return;
    // The journal is read after the steps: these are the `step-started` read
    // before this read of `step.json`.
    final starts = session.startsOf(step.id);
    if (known == null) {
      session.steps[dir] = _stepsById[step.id] = _Step(step, dir)
        ..startsRead = starts;
      out.add(StepAdded(step));
      return;
    }
    known.startsRead = starts;
    if (step != known.step) {
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

/// The time to the second in the name of the session directory [dir]:
/// `YYYY-MM-DDTHH-MM-SS`, which sorts as the time does.
String _createdStamp(String dir) {
  final name = _name(Directory(dir));
  // `<workflow>-<stamp>-<id>`: the stamp is 19 characters before `-<id>`.
  return name.substring(name.length - 56, name.length - 37);
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

/// The change a complete [line] of the journal of the session [sessionId]
/// gives: an event, or `log-corrupted` when the line is not a JSON object
/// with string `time` and `event`. [number] counts lines from 1.
Change _journalChange(String sessionId, int number, Uint8List line) {
  if (_decode(line) case final Map<String, Object?> json
      when json['time'] is String && json['event'] is String) {
    return EventAdded(sessionId: sessionId, event: Event.fromJson(json));
  }
  return LogCorrupted(
    sessionId: sessionId,
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
  _Session(this.session, this.dir)
    : journal = Tail(p.join(dir, eventsFileName));

  final Session session;

  final String dir;

  /// Its journal, read up to the end of the last complete line.
  final Tail journal;

  /// Its steps, by directory.
  final Map<String, _Step> steps = {};

  /// How many `step-started` of each of its steps have been read, by id.
  final Map<String, int> _starts = {};

  /// Ids of its steps whose last event read is `step-started`.
  final Set<String> _running = {};

  /// The `outputId` of the last `step-finished` read of each of its steps,
  /// by id.
  final Map<String, String> _outputs = {};

  /// Ids of its documents.
  final Set<String> documents = {};

  /// Whether its last event has been read.
  bool lastRead = false;

  /// Whether it has been read in full since its last event was: nothing
  /// more is written to it.
  bool ended = false;

  /// Takes the `step-started` of the step [stepId].
  void stepStarted(String stepId) {
    _starts.update(stepId, (n) => n + 1, ifAbsent: () => 1);
    _running.add(stepId);
  }

  /// Takes the `step-finished` with [outputId], or the `step-failed`
  /// (`null`), of the step [stepId].
  void stepEnded(String stepId, String? outputId) {
    _running.remove(stepId);
    if (outputId != null) _outputs[stepId] = outputId;
  }

  /// How many `step-started` of the step [stepId] have been read.
  int startsOf(String stepId) => _starts[stepId] ?? 0;

  /// Whether the `step.json` of [given] may have been rewritten since it
  /// was read, and so is read again (D3):
  /// - it was given without the `outputId` of its last `step-finished`:
  ///   `step.json` is rewritten with it after that event is written;
  /// - it runs again (a `step-started` that is not its first), and
  ///   `step.json` is rewritten with the `after` of the new call right after
  ///   that event: read again while that run goes on, and once after a
  ///   `step-started` read since `step.json` was.
  bool mayChange(_Step given) {
    final id = given.step.id;
    final output = _outputs[id];
    if (output != null && given.step.outputId != output) return true;
    final starts = startsOf(id);
    return starts > 1 && (starts > given.startsRead || _running.contains(id));
  }
}

/// A step given, as it was last given.
final class _Step {
  _Step(this.step, this.dir);

  Step step;

  final String dir;

  /// How many `step-started` of it had been read when its `step.json` was
  /// last read.
  int startsRead = 0;
}
