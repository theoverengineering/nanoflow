import 'dart:ffi';
import 'dart:io';

/// The stdin of this process, read to its end through a descriptor of its
/// own, which is closed then; fd 0 itself stays open. The stream is empty
/// when the process was started with its stdin closed.
///
/// Dart's `stdin`, read to its end, closes fd 0 on another thread. A
/// process this one starts at that moment can come up with its stdin
/// closed, when a pipe made for its start lands on fd 0 as it is closed;
/// a Dart program started so waits forever once it reads its stdin. With
/// fd 0 kept open, nothing can land on it.
///
/// A file's `openRead` is not used: after a read error its stream never
/// ends.
Stream<List<int>> processStdin() async* {
  if (!_startedWithStdin()) return;
  final file = await File('/dev/stdin').open();
  try {
    while (true) {
      final chunk = await file.read(64 * 1024);
      if (chunk.isEmpty) return;
      yield chunk;
    }
  } finally {
    await file.close();
  }
}

/// Whether fd 0 is the stdin this process was started with.
///
/// A descriptor that outlives `exec` is never close-on-exec. When the
/// process was started with fd 0 closed, the Dart VM takes fd 0 for a pipe
/// of its own, which is; reading that pipe would take the VM's own
/// wake-ups, and nothing would happen in the process again.
bool _startedWithStdin() {
  final flags = _fcntl(0, _getFd);
  return flags != -1 && flags & _closeOnExec == 0;
}

final _fcntl = DynamicLibrary.process()
    .lookupFunction<Int Function(Int, Int), int Function(int, int)>('fcntl');

/// `F_GETFD` and `FD_CLOEXEC`, the same on macOS and Linux.
const _getFd = 1;
const _closeOnExec = 1;
