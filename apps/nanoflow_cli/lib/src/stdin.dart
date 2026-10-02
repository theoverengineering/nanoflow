import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// The stdin of this process, read to its end from fd 0 itself, which is
/// never closed. The stream is empty when the process was started with its
/// stdin closed; when stdin cannot be read, its one error is a
/// [FileSystemException] whose [OSError] says why.
///
/// Dart's `stdin`, read to its end, closes fd 0 on another thread. A
/// process this one starts at that moment can come up with its stdin
/// closed, when a pipe made for its start lands on fd 0 as it is closed;
/// a Dart program started so waits forever once it reads its stdin. With
/// fd 0 kept open, nothing can land on it.
///
/// fd 0 is read with `read(2)`, on an isolate of its own, where waiting for
/// input holds up nothing else. That reads every kind of stdin: a file, a
/// pipe, a terminal, `/dev/null`, a socket (a Node.js parent gives one),
/// and one a parent left non-blocking, which is read again after a short
/// wait. Opening `/dev/stdin` instead fails for a socket.
Stream<List<int>> processStdin() async* {
  if (!_startedWithStdin()) return;
  final (:bytes, :error) = await Isolate.run(_readStdin, debugName: 'stdin');
  if (error != null) throw FileSystemException('cannot read', 'stdin', error);
  if (bytes.isNotEmpty) yield bytes;
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

/// Reads fd 0 to its end: what it holds, or why it cannot be read.
({Uint8List bytes, OSError? error}) _readStdin() {
  const size = 64 * 1024;
  final buffer = _malloc(size);
  try {
    final bytes = BytesBuilder();
    while (true) {
      final count = _read(0, buffer, size);
      if (count > 0) {
        bytes.add(buffer.asTypedList(count));
        continue;
      }
      if (count == 0) return (bytes: bytes.takeBytes(), error: null);
      final errno = _errno().value;
      if (errno == _interrupted) continue;
      if (errno == _wouldBlock) {
        sleep(const Duration(milliseconds: 10));
        continue;
      }
      return (bytes: Uint8List(0), error: OSError(_message(errno), errno));
    }
  } finally {
    _free(buffer);
  }
}

/// The system's words for [errno]: `Is a directory`.
String _message(int errno) {
  final text = _strerror(errno);
  var length = 0;
  while (text[length] != 0) {
    length++;
  }
  return String.fromCharCodes(text.asTypedList(length));
}

final _libc = DynamicLibrary.process();

final _fcntl = _libc
    .lookupFunction<Int Function(Int, Int), int Function(int, int)>('fcntl');

final _read = _libc
    .lookupFunction<
      IntPtr Function(Int, Pointer<Uint8>, Size),
      int Function(int, Pointer<Uint8>, int)
    >('read');

/// Where `errno` of this thread is, read right after the call that set it:
/// a leaf call runs no code of the VM that could set it again.
final _errno = _libc
    .lookupFunction<Pointer<Int> Function(), Pointer<Int> Function()>(
      Platform.isMacOS ? '__error' : '__errno_location',
      isLeaf: true,
    );

final _strerror = _libc
    .lookupFunction<Pointer<Uint8> Function(Int), Pointer<Uint8> Function(int)>(
      'strerror',
    );

final _malloc = _libc
    .lookupFunction<
      Pointer<Uint8> Function(Size),
      Pointer<Uint8> Function(int)
    >('malloc');

final _free = _libc
    .lookupFunction<
      Void Function(Pointer<Uint8>),
      void Function(Pointer<Uint8>)
    >('free');

/// `F_GETFD` and `FD_CLOEXEC`, the same on macOS and Linux.
const _getFd = 1;
const _closeOnExec = 1;

/// `EINTR`, the same on macOS and Linux, and `EAGAIN` (`EWOULDBLOCK`).
const _interrupted = 4;
final _wouldBlock = Platform.isMacOS ? 35 : 11;
