// Holds an exclusive lock on the file its first argument names, as another
// process that works with a session's lock file does: the byte at the offset
// its second argument gives, or the whole file when there is none. Prints
// `locked` once it holds the lock, and holds it until it is killed.
// test/owner_lock_test.dart runs it.
import 'dart:io';

Future<void> main(List<String> args) async {
  final file = await File(args[0]).open(mode: FileMode.append);
  if (args.length > 1) {
    final offset = int.parse(args[1]);
    await file.lock(FileLock.exclusive, offset, offset + 1);
  } else {
    await file.lock(FileLock.exclusive);
  }
  print('locked');
  await stdin.drain<void>();
}
