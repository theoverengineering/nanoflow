import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import 'atomic.dart';
import 'owner_lock.dart';
import 'session_handle.dart';

/// The sessions in a `runs` directory, as the process that runs them keeps
/// them.
final class FsStore {
  FsStore(this.runsDir, {this._owner, this._clock = systemClock});

  /// The `runs` directory in the project directory.
  final String runsDir;

  /// The process that runs the sessions the store holds: written into the
  /// lock file of each, `.owner.lock`, while the store holds it, and cleared
  /// when the handle lets the session go. `null` writes none: the file stays
  /// empty.
  final Owner? _owner;

  final Clock _clock;

  /// Creates a session of the workflow [workflow]: one call of it.
  ///
  /// The session's lock is taken before anything is written to it: the
  /// handle holds it, so no other process can open the session (see
  /// [openSession]). The store's owner is written into the lock file. Builds
  /// the whole session under `runs/.tmp-<id>/` and renames it into place:
  /// `session.json` with [graph], the `documents` directory with the input
  /// document (when [input] is given), the empty `steps` directory and
  /// `log.jsonl` with `session-started` and [code]. The session directory's
  /// name and the time of `session-started` are the time the session is
  /// created; creates [runsDir] when there is none.
  Future<SessionHandle> createSession({
    required String workflow,
    required Map<String, Object?>? graph,
    required ({Object? value})? input,
    required String? code,
  }) async {
    final id = newId();
    final createdAt = _clock();
    late final SessionHandle built;
    RandomAccessFile? lock;
    final String dir;
    try {
      dir = await buildDirAtomically(
        runsDir,
        id: id,
        name: sessionDirName(workflow, createdAt, id),
        createParent: true,
        build: (dir) async {
          // A lock on an open file outlives the rename of its directory.
          final taken = lock = await lockSession(dir, id, owner: _owner);
          await Directory(p.join(dir, documentsDirName)).create();
          await Directory(p.join(dir, stepsDirName)).create();
          final inputId = input == null
              ? null
              : await writeDocumentAt(dir, id, input.value);
          final session = Session(
            id: id,
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
          built = sessionHandleAt(dir, session, _clock, taken);
        },
      );
    } catch (_) {
      if (lock case final taken?) await unlockSession(id, taken);
      rethrow;
    }
    return movedSessionHandle(built, dir);
  }

  /// The session [sessionId], or `null` when [runsDir] has none.
  ///
  /// The session's directory is the one whose name ends with the id; a name
  /// that starts with `.` belongs to a session that was never finished being
  /// created. Takes the session's lock, which the handle holds, writes the
  /// store's owner into the lock file in place of the owner before, and then
  /// cuts an incomplete last line off the journal.
  ///
  /// Throws a [SessionBusyException], having changed nothing, when another
  /// process holds the lock: one that created or opened the session and
  /// still runs. The system drops the lock of a process that dies. Throws it
  /// too when this isolate holds the session already, through a handle not
  /// yet let go. A session it cannot read is a [FileSystemException].
  Future<SessionHandle?> openSession(String sessionId) async {
    final dirs = await _sessionDirs();
    final dir = dirs.where((dir) => dir.id == sessionId).firstOrNull;
    return dir == null
        ? null
        : loadSessionHandle(dir.path, sessionId, _clock, _owner);
  }

  /// Ids of the sessions of [workflow] whose journal has no
  /// `session-finished` or `session-failed`, newest first: by the time of
  /// their `session-started`.
  ///
  /// Takes no lock: a session another process owns is listed too. A
  /// session whose `session.json` or journal cannot be read is left out.
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
