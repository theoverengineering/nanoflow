import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import 'scanner.dart';
import 'tail.dart';

/// The storage of one graph in its `runs` directory, as the engine writes it:
/// a feed of changes, and data on request.
///
/// The reader only reads. It follows the directory by file system events and
/// polls it as well, since events come late and get merged.
final class FsReader {
  FsReader({
    required this.runsDir,
    required this.graphName,
    this.pollInterval = const Duration(milliseconds: 500),
  }) : _scanner = Scanner(runsDir: runsDir, graphName: graphName);

  /// The `runs` directory next to the graph file.
  final String runsDir;

  /// The graph's name: its sessions are the directories named after it.
  final String graphName;

  /// How often the reader looks for changes when no file system event tells
  /// it to.
  final Duration pollInterval;

  final Scanner _scanner;

  late final Stream<Change> _changes = follow(
    runsDir,
    recursive: true,
    interval: pollInterval,
    pass: _scanner.scan,
  );

  /// Everything already on disk, then new changes as they appear. Single
  /// subscription; cancelling stops all watching. Works when [runsDir] does
  /// not exist yet (it starts emitting once it appears).
  ///
  /// The events of a run come in the order of its journal, after the run's
  /// `run-added`; anything else may come in any order. A journal line that is
  /// still being written is given once it is complete. A file that is not its
  /// model, such as a `run.json` that is not a run, comes as an error on the
  /// stream, once, and the entity is not given until the file is fixed; the
  /// feed goes on.
  Stream<Change> changes() => _changes;

  /// The graph the session [sessionId] holds.
  ///
  /// Throws an [ArgumentError] when the graph has no such session.
  Future<Map<String, Object?>> sessionGraph(String sessionId) async =>
      (await readModel(
        p.join(await _sessionDir(sessionId), sessionFileName),
        Session.fromJson,
      )).graph;

  /// The value of the document [documentId] of the session [sessionId].
  ///
  /// Throws an [ArgumentError] when the graph has no such session, and a
  /// [PathNotFoundException] when the session has no such document.
  Future<Object?> documentValue(String sessionId, String documentId) async =>
      (await readModel(
        p.join(
          await _sessionDir(sessionId),
          documentsDirName,
          documentFileName(documentId),
        ),
        Document.fromJson,
      )).value;

  /// Accumulated log text first, then appended text as it grows, until
  /// cancelled. Decodes UTF-8 across chunk boundaries.
  ///
  /// Gives nothing until the log file appears: the engine creates it when the
  /// step's command first writes to it. A step without a log gives nothing and
  /// ends. Errors with an [ArgumentError] when there is no such step.
  Stream<String> stepLog(String sessionId, String runId, String stepId) async* {
    final path = logPath(stepId) ?? await _logOnDisk(sessionId, runId, stepId);
    if (path == null) return;
    final tail = Tail(path);
    yield* const Utf8Decoder(allowMalformed: true).bind(
      follow<Uint8List>(
        p.dirname(path),
        recursive: false,
        interval: pollInterval,
        pass: (out) async {
          final bytes = await tail.read();
          if (bytes.isNotEmpty) out.add(bytes);
        },
      ),
    );
  }

  // Filesystem paths, known once the feed has reported the entity; null
  // before.

  /// The directory of the session [sessionId].
  String? sessionPath(String sessionId) => _scanner.sessionPath(sessionId);

  /// The directory of the run [runId].
  String? runPath(String runId) => _scanner.runPath(runId);

  /// The directory of the step [stepId].
  String? stepPath(String stepId) => _scanner.stepPath(stepId);

  /// The log file of the step [stepId], which may not exist yet; `null` also
  /// for a step without a log.
  String? logPath(String stepId) => _scanner.logPath(stepId);

  /// The file of the document [documentId] of the session [sessionId].
  String? documentPath(String sessionId, String documentId) =>
      _scanner.documentPath(sessionId, documentId);

  /// The log file of a step the feed has not given, from its `step.json`.
  Future<String?> _logOnDisk(
    String sessionId,
    String runId,
    String stepId,
  ) async {
    final dir = await _stepDir(sessionId, runId, stepId);
    final log = (await readModel(p.join(dir, stepFileName), Step.fromJson)).log;
    return log == null ? null : p.join(dir, log);
  }

  // The directories of entities, given or not: a step's command may be
  // running before the feed gives the step.

  Future<String> _sessionDir(String sessionId) async =>
      sessionPath(sessionId) ??
      await _findDir(
        runsDir,
        sessionId,
        (name) => isSessionDirOf(name, graphName),
      ) ??
      (throw ArgumentError.value(
        sessionId,
        'sessionId',
        'no session of graph $graphName in $runsDir',
      ));

  Future<String> _runDir(String sessionId, String runId) async =>
      runPath(runId) ??
      await _findDir(await _sessionDir(sessionId), runId) ??
      (throw ArgumentError.value(
        runId,
        'runId',
        'no such run in session $sessionId',
      ));

  Future<String> _stepDir(
    String sessionId,
    String runId,
    String stepId,
  ) async =>
      stepPath(stepId) ??
      await _findDir(
        p.join(await _runDir(sessionId, runId), stepsDirName),
        stepId,
      ) ??
      (throw ArgumentError.value(
        stepId,
        'stepId',
        'no such step in run $runId',
      ));
}

/// The directory in [parent] whose name ends with [id] and that [accepts]
/// takes, or `null`.
Future<String?> _findDir(
  String parent,
  String id, [
  bool Function(String name)? accepts,
]) async {
  final List<String> dirs;
  try {
    dirs = await builtDirs(parent);
  } on PathNotFoundException {
    return null;
  }
  for (final dir in dirs) {
    final name = p.basename(dir);
    if (idOfDirName(name) == id && (accepts?.call(name) ?? true)) return dir;
  }
  return null;
}
