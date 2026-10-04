import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_process/nanoflow_process.dart';
import 'package:path/path.dart' as p;

import 'owners.dart';
import 'scanner.dart';
import 'tail.dart';

/// The sessions in a `runs` directory, as the library writes them: a feed of
/// changes, and data on request.
///
/// The reader only reads. It follows the directory by file system events and
/// polls it as well, since events come late and get merged. Whether the
/// process that owns a session is alive it learns from the OS, which tells
/// when the process exits.
///
/// Never run a reader in a process that owns sessions of the same `runs`:
/// reading a session's `.owner.lock` there drops the lock that process holds.
final class FsReader {
  /// A reader of [runsDir] that asks [processes] whether the owners of
  /// sessions are alive. Without [processes] it makes the adapter of this OS,
  /// [Processes.forPlatform], and closes it when the feed is cancelled: the
  /// cancel completes once it has closed. An adapter it is given is the
  /// caller's to close.
  FsReader({
    required String runsDir,
    Duration pollInterval = const Duration(milliseconds: 500),
    Processes? processes,
  }) : this._(
         runsDir,
         pollInterval,
         processes ?? Processes.forPlatform(),
         ownsProcesses: processes == null,
       );

  FsReader._(
    this.runsDir,
    this.pollInterval,
    this._processes, {
    required this._ownsProcesses,
  });

  /// The `runs` directory in the project directory.
  final String runsDir;

  /// How often the reader looks for changes when no file system event tells
  /// it to.
  final Duration pollInterval;

  /// Tells whether the processes that own sessions run.
  final Processes _processes;

  /// Whether the reader made [_processes], and so closes it.
  final bool _ownsProcesses;

  late final Owners _owners = Owners(_processes);

  late final Scanner _scanner = Scanner(runsDir: runsDir, owners: _owners);

  late final Stream<Change> _changes = _follow();

  /// Everything already on disk, then new changes as they appear, for every
  /// session in [runsDir]. Single subscription; cancelling stops all
  /// watching. Works when [runsDir] does not exist yet (it starts emitting
  /// once it appears).
  ///
  /// The events of a session come in the order of its journal, after the
  /// session's `session-added`; anything else may come in any order. A
  /// journal line that is still being written is given once it is complete.
  /// A file that is not its model, such as an `effect.json` that is not an
  /// effect, comes as an error on the stream, once, and the entity is not given
  /// until the file is fixed; the feed goes on.
  ///
  /// While a session's journal goes on, `owner-changed` tells its owner from
  /// `.owner.lock` and whether the owner's process is alive: first after the
  /// session's other changes of the first read, then each time either
  /// changes; the exit of the process makes the reader look at once. The
  /// owner is looked at before the session's journal is read, and told after
  /// it: an owner writes the last event before it lets the session go or
  /// exits, so a session that ended comes with its last event and no
  /// `owner-changed` that says its owner is gone.
  Stream<Change> changes() => _changes;

  /// The value of the document [documentId] of the session [sessionId].
  ///
  /// Throws an [ArgumentError] when [runsDir] has no such session, and a
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
  /// Gives nothing while there is no log file: it is created when the effect
  /// first prints. Errors with an [ArgumentError] when there is no such
  /// session or effect.
  Stream<String> effectLog(String sessionId, String effectId) async* {
    final path = logPath(effectId) ?? await _logOnDisk(sessionId, effectId);
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

  /// The feed, which stops watching owners when it is cancelled.
  Stream<Change> _follow() async* {
    try {
      yield* followRuns(
        runsDir,
        pollInterval,
        _scanner.scan,
        wake: _owners.news,
      );
    } finally {
      _owners.close();
      if (_ownsProcesses) await _processes.close();
    }
  }

  // Filesystem paths, known once the feed has reported the entity; null
  // before.

  /// The directory of the session [sessionId].
  String? sessionPath(String sessionId) => _scanner.sessionPath(sessionId);

  /// The directory of the effect [effectId].
  String? effectPath(String effectId) => _scanner.effectPath(effectId);

  /// The log file of the effect [effectId], which may not exist yet.
  String? logPath(String effectId) => _scanner.logPath(effectId);

  /// The file of the document [documentId] of the session [sessionId].
  String? documentPath(String sessionId, String documentId) =>
      _scanner.documentPath(sessionId, documentId);

  /// The log file of an effect the feed has not given, from its `effect.json`.
  Future<String> _logOnDisk(String sessionId, String effectId) async {
    final dir = await _effectDir(sessionId, effectId);
    final effect = await readModel(
      p.join(dir, effectFileName),
      Effect.fromJson,
    );
    return p.join(dir, effect.log);
  }

  // The directories of entities, given or not: an effect may be running before
  // the feed gives it.

  Future<String> _sessionDir(String sessionId) async =>
      sessionPath(sessionId) ??
      await _findDir(runsDir, sessionId, isSessionDirName) ??
      (throw ArgumentError.value(
        sessionId,
        'sessionId',
        'no session in $runsDir',
      ));

  Future<String> _effectDir(String sessionId, String effectId) async =>
      effectPath(effectId) ??
      await _findDir(
        p.join(await _sessionDir(sessionId), effectsDirName),
        effectId,
      ) ??
      (throw ArgumentError.value(
        effectId,
        'effectId',
        'no such effect in session $sessionId',
      ));
}

/// A reader of [runsDir] that closes [processes] when its feed is
/// cancelled, as an [FsReader] given none closes the adapter it makes: lets
/// tests see that it does.
FsReader readerOwning(
  Processes processes, {
  required String runsDir,
  Duration pollInterval = const Duration(milliseconds: 500),
}) => FsReader._(runsDir, pollInterval, processes, ownsProcesses: true);

/// What [scan] gives, run as the feed of [runsDir] runs it: when listened
/// to, on every file system event under [runsDir] but those of an effect's
/// `effect.log`, on every event of [wake], and every [interval].
///
/// A running effect writes its log all the time, and a scan does not read
/// logs: [FsReader.effectLog] follows a log by itself.
Stream<T> followRuns<T>(
  String runsDir,
  Duration interval,
  Future<void> Function(EventSink<T> out) scan, {
  Stream<void>? wake,
}) => follow(
  runsDir,
  recursive: true,
  interval: interval,
  ignore: (event) => p.basename(event.path) == logFileName,
  wake: wake,
  pass: scan,
);

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
