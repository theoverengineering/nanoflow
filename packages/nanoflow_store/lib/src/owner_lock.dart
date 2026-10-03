// One process owns a session (spec §4.6): while it does, it holds an OS lock
// on a file in the session's directory. The system drops the lock when the
// process dies, so a session is free again after a crash.
//
// The lock belongs to the process, not to the file descriptor: another lock
// the process takes on the same file succeeds, and closing any descriptor
// the process has of the file drops the lock, however it was taken. So the
// sessions this isolate holds are kept apart, and asking for one of them
// again is refused without opening its lock file.

import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

/// Another process owns the session, or this one does already: it holds the
/// session's lock.
final class SessionBusyException implements Exception {
  const SessionBusyException(this.sessionId);

  final String sessionId;

  @override
  String toString() =>
      'SessionBusyException: another process owns the session $sessionId, '
      'or this one does already';
}

/// The ids of the sessions whose lock this isolate holds or is taking.
final _held = <String>{};

/// Takes the lock of the session [sessionId] in [dir] for this process and
/// gives the open lock file, which holds it until [unlockSession].
///
/// Throws a [SessionBusyException] when another process holds the lock, or
/// this isolate holds it already: then it does not open the lock file, whose
/// closing would drop the lock it holds.
Future<RandomAccessFile> lockSession(String dir, String sessionId) async {
  if (!_held.add(sessionId)) throw SessionBusyException(sessionId);
  try {
    final file = await File(p.join(dir, ownerLockFileName))
        .open(mode: FileMode.append);
    try {
      await file.lock(FileLock.exclusive);
    } on FileSystemException catch (e) {
      await file.close();
      if (_heldElsewhere.contains(e.osError?.errorCode)) {
        throw SessionBusyException(sessionId);
      }
      rethrow;
    }
    return file;
  } catch (_) {
    _held.remove(sessionId);
    rethrow;
  }
}

/// Gives up the lock of the session [sessionId] that [lockSession] gave as
/// [file].
Future<void> unlockSession(String sessionId, RandomAccessFile file) async {
  try {
    await file.close();
  } finally {
    _held.remove(sessionId);
  }
}

/// The codes `fcntl` fails with when another process holds the lock: EAGAIN,
/// whose number differs between macOS and Linux, and EACCES.
final _heldElsewhere = {Platform.isMacOS ? 35 : 11, 13};
