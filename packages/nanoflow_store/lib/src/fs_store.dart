import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import 'atomic.dart';
import 'fs_session.dart';
import 'owner_lock.dart';

/// The sessions in a `runs` directory, as the process that runs them keeps
/// them.
final class FsStore implements SessionStore {
  FsStore(this.runsDir, {this._clock = systemClock});

  /// The `runs` directory in the project directory.
  final String runsDir;

  final Clock _clock;

  /// Creates a session of the workflow [workflow]: one call of it.
  ///
  /// The session's lock is taken before anything is written to it: the
  /// session holds it, so no other process can open the session (see
  /// [openSession]). [owner] is written into the lock file, `.owner.lock`,
  /// and cleared when the session is let go; `null` writes none: the file
  /// stays empty. Builds the whole session under `runs/.tmp-<id>/` and
  /// renames it into place: `session.json` with [graph], the `documents`
  /// directory with the input document (when [input] is given), the empty
  /// `effects` directory and `log.jsonl` with `session-started` and [code].
  /// The session directory's name and the time of `session-started` are the
  /// time the session is created; creates [runsDir] when there is none.
  ///
  /// The id is [id] when given: an [ArgumentError] when it is not an id
  /// ([isId]), and a [SessionExistsException] when [runsDir] has a directory
  /// with it, one being built too.
  @override
  Future<FsSession> createSession({
    required String workflow,
    required Map<String, Object?>? graph,
    required ({Object? value})? input,
    required String? code,
    String? id,
    Owner? owner,
  }) async {
    if (id != null) {
      if (!isId(id)) throw ArgumentError.value(id, 'id', 'not an id');
      if (await _hasDirOf(id)) throw SessionExistsException(id);
    }
    final sessionId = id ?? newId();
    final createdAt = _clock();
    late final FsSession built;
    RandomAccessFile? lock;
    final String dir;
    try {
      dir = await buildDirAtomically(
        runsDir,
        id: sessionId,
        name: sessionDirName(workflow, createdAt, sessionId),
        createParent: true,
        build: (dir) async {
          // A lock on an open file outlives the rename of its directory.
          final taken = lock = await lockSession(dir, sessionId, owner: owner);
          await Directory(p.join(dir, documentsDirName)).create();
          await Directory(p.join(dir, effectsDirName)).create();
          final inputId = input == null
              ? null
              : await writeDocumentAt(dir, sessionId, input.value);
          final session = Session(
            id: sessionId,
            workflow: workflow,
            graph: graph,
            inputId: inputId,
          );
          await writeJsonAtomically(
            p.join(dir, sessionFileName),
            session.toJson(),
          );
          await startJournal(
            p.join(dir, eventsFileName),
            SessionStarted(time: createdAt, code: code),
          );
          built = fsSessionAt(dir, session, _clock, taken);
        },
      );
    } catch (_) {
      if (lock case final taken?) await unlockSession(sessionId, taken);
      rethrow;
    }
    return movedFsSession(built, dir);
  }

  /// The session [sessionId], or `null` when [runsDir] has none.
  ///
  /// The session's directory is the one whose name ends with the id; a name
  /// that starts with `.` belongs to a session that was never finished being
  /// created. Takes the session's lock, which the session holds, writes
  /// [owner] into the lock file in place of the owner before, and then cuts
  /// an incomplete last line off the journal.
  ///
  /// Throws a [SessionBusyException], having changed nothing, when another
  /// process holds the lock: one that created or opened the session and
  /// still runs. The system drops the lock of a process that dies. Throws it
  /// too when this isolate holds the session already, through a session not
  /// yet let go. A session it cannot read is a [FileSystemException].
  @override
  Future<FsSession?> openSession(String sessionId, {Owner? owner}) async {
    final dirs = await _sessionDirs();
    final dir = dirs.where((dir) => dir.id == sessionId).firstOrNull;
    return dir == null
        ? null
        : loadFsSession(dir.path, sessionId, _clock, owner);
  }

  /// Ids of the sessions of [workflow] whose journal has no
  /// `session-finished` or `session-failed`, newest first: by the time of
  /// their `session-started`.
  ///
  /// Takes no lock: a session another process owns is listed too. A
  /// session whose `session.json` or journal cannot be read is left out.
  @override
  Future<List<String>> unfinishedSessions(String workflow) async {
    final found = <({String id, DateTime startedAt, String name})>[];
    for (final dir in await _sessionDirs()) {
      try {
        final session = await readModel(
          p.join(dir.path, sessionFileName),
          Session.fromJson,
        );
        if (session.workflow != workflow) continue;
        final events = await readJournal(p.join(dir.path, eventsFileName));
        if (events.any((e) => e is SessionFinished || e is SessionFailed)) {
          continue;
        }
        final started = events.whereType<SessionStarted>().firstOrNull;
        found.add((
          id: session.id,
          // A journal without session-started is written by hand: oldest.
          startedAt: started?.time ?? DateTime.utc(0),
          name: p.basename(dir.path),
        ));
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      } on StoreCorruptedException {
        continue;
      }
    }
    found.sort((a, b) {
      final byTime = b.startedAt.compareTo(a.startedAt);
      return byTime != 0 ? byTime : b.name.compareTo(a.name);
    });
    return [for (final session in found) session.id];
  }

  /// Whether [runsDir] has a directory, built or being built, whose name
  /// ends with [id].
  Future<bool> _hasDirOf(String id) async {
    final runs = Directory(runsDir);
    if (!await runs.exists()) return false;
    return runs.list().any(
      (entity) =>
          entity is Directory && p.basename(entity.path).endsWith('-$id'),
    );
  }

  /// The built session directories in [runsDir]; none when there is no
  /// [runsDir].
  Future<List<({String id, String path})>> _sessionDirs() async {
    final runs = Directory(runsDir);
    if (!await runs.exists()) return const [];
    return [
      await for (final entity in runs.list())
        if (idOfBuiltDir(entity) case final id?
            when isSessionDirName(p.basename(entity.path)))
          (id: id, path: entity.path),
    ];
  }
}
