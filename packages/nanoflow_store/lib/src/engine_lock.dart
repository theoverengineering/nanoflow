// One engine process drives a session (README «Правила»): while it does, it
// holds an OS lock on a file in the session's directory. The system drops
// the lock when the process dies, so a session is free again after a crash.

import 'dart:io';

import 'package:path/path.dart' as p;

/// The file in a session's directory whose lock the engine driving the
/// session holds. Its name starts with `.`: readers skip it.
const engineLockFileName = '.engine.lock';

/// Another engine process drives the session: it holds the session's lock.
final class SessionBusyException implements Exception {
  const SessionBusyException(this.sessionId);

  final String sessionId;

  @override
  String toString() =>
      'SessionBusyException: session $sessionId is being run by another '
      'engine';
}

/// Takes the lock of the session [sessionId] in [dir] for this process and
/// gives the open lock file, which holds it until it is closed.
///
/// Throws a [SessionBusyException] when another process holds the lock.
Future<RandomAccessFile> lockSession(String dir, String sessionId) async {
  final file = await File(p.join(dir, engineLockFileName))
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
