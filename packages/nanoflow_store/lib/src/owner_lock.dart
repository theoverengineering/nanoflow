// One process owns a session (spec §4.6): while it does, it holds an OS lock
// on a file in the session's directory. The system drops the lock when the
// process dies, so a session is free again after a crash.

import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

/// Another process owns the session: it holds the session's lock.
final class SessionBusyException implements Exception {
  const SessionBusyException(this.sessionId);

  final String sessionId;

  @override
  String toString() =>
      'SessionBusyException: another process owns the session $sessionId';
}

/// Takes the lock of the session [sessionId] in [dir] for this process and
/// gives the open lock file, which holds it until it is closed.
///
/// Throws a [SessionBusyException] when another process holds the lock.
Future<RandomAccessFile> lockSession(String dir, String sessionId) async {
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
}

/// The codes `fcntl` fails with when another process holds the lock: EAGAIN,
/// whose number differs between macOS and Linux, and EACCES.
final _heldElsewhere = {Platform.isMacOS ? 35 : 11, 13};
