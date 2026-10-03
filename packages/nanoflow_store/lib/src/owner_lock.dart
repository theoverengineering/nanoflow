// One process owns a session (spec §4.6): while it does, it holds an OS lock
// on a file in the session's directory. The system drops the lock when the
// process dies, so a session is free again after a crash.
//
// The lock belongs to the process, not to the file descriptor: another lock
// the process takes on the same file succeeds, and closing any descriptor
// the process has of the file drops the lock, however it was taken. So the
// sessions this isolate holds are kept apart, and asking for one of them
// again is refused without opening its lock file.
//
// The lock covers one byte, at [ownerLockOffset], and not the whole file: the
// file's content is not under the lock, so it can be read where locks are
// mandatory. The content says who holds the lock: the owner's pid and the
// time its process started, or nothing when no one does.

import 'dart:convert';
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
/// Once it holds the lock, it writes [owner] into the lock file, replacing
/// what the owner before left there. Without an [owner] it leaves the file
/// empty: a record that is left says another process owns the session.
///
/// Throws a [SessionBusyException] when another process holds the lock, or
/// this isolate holds it already: then it does not open the lock file, whose
/// closing would drop the lock it holds.
Future<RandomAccessFile> lockSession(
  String dir,
  String sessionId, {
  Owner? owner,
}) async {
  if (!_held.add(sessionId)) throw SessionBusyException(sessionId);
  try {
    final file = await File(p.join(dir, ownerLockFileName))
        .open(mode: FileMode.append);
    try {
      await file.lock(FileLock.exclusive, ownerLockOffset, ownerLockOffset + 1);
    } on FileSystemException catch (e) {
      await file.close();
      if (_heldElsewhere.contains(e.osError?.errorCode)) {
        throw SessionBusyException(sessionId);
      }
      rethrow;
    }
    try {
      await _writeOwner(file, owner);
    } catch (_) {
      // Closing drops the lock.
      await file.close();
      rethrow;
    }
    return file;
  } catch (_) {
    _held.remove(sessionId);
    rethrow;
  }
}

/// Gives up the lock of the session [sessionId] that [lockSession] gave as
/// [file]: empties the file, which says no one owns the session, and closes
/// it.
Future<void> unlockSession(String sessionId, RandomAccessFile file) async {
  try {
    try {
      await file.truncate(0);
    } finally {
      // The lock goes even when the file could not be emptied.
      await file.close();
    }
  } finally {
    _held.remove(sessionId);
  }
}

/// Writes [owner] as JSON, without a newline, into [file], which is open and
/// whose lock this process holds; empties it for none.
///
/// The record is written from position 0, and then the file is cut at its
/// length: the old record is there until the new one is, and no tail of it is
/// left, as a shorter record is written over a longer one. The file is not
/// replaced by a renamed one: the lock belongs to the open file.
///
/// Dart's `FileMode.append` opens the file to read and write, creating it
/// when it is missing, and moves to its end only once, as it opens; it does
/// not make every write go to the end, so the position can be set to 0.
Future<void> _writeOwner(RandomAccessFile file, Owner? owner) async {
  if (owner == null) {
    await file.truncate(0);
    return;
  }
  final record = utf8.encode(jsonEncode(owner.toJson()));
  await file.setPosition(0);
  await file.writeFrom(record);
  await file.truncate(record.length);
}

/// The codes `fcntl` fails with when another process holds the lock: EAGAIN,
/// whose number differs between macOS and Linux, and EACCES.
final _heldElsewhere = {Platform.isMacOS ? 35 : 11, 13};
