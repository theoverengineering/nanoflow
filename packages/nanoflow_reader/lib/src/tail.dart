import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

const _newline = 0x0a;

/// A file that is only ever appended to, read on from where the last read
/// stopped.
///
/// A file that does not exist yet reads as empty. Bytes before the offset are
/// never read again: should the file get shorter than that, nothing is read
/// until it is longer again.
final class Tail {
  Tail(this.path);

  final String path;

  /// How many bytes from the start have been given.
  int _offset = 0;

  /// The bytes appended since the last read.
  Future<Uint8List> read() async {
    final bytes = await _rest();
    _offset += bytes.length;
    return bytes;
  }

  /// The complete lines appended since the last read, without their `\n`.
  ///
  /// A last line without `\n` is not given: it is read again, whole, once it
  /// is complete. So a writer may cut it off and write other lines instead.
  Future<List<Uint8List>> readLines() async {
    final bytes = await _rest();
    final lines = <Uint8List>[];
    var start = 0;
    for (
      var end = bytes.indexOf(_newline);
      end != -1;
      end = bytes.indexOf(_newline, start)
    ) {
      lines.add(Uint8List.sublistView(bytes, start, end));
      start = end + 1;
    }
    _offset += start;
    return lines;
  }

  /// The bytes of the file after [_offset].
  Future<Uint8List> _rest() async {
    final RandomAccessFile file;
    try {
      file = await File(path).open();
    } on PathNotFoundException {
      return Uint8List(0);
    }
    try {
      final length = await file.length();
      if (length <= _offset) return Uint8List(0);
      await file.setPosition(_offset);
      return await file.read(length - _offset);
    } finally {
      await file.close();
    }
  }
}

/// A stream of what [pass] gives. [pass] runs when the stream is listened to,
/// then again on every file system event under [dir] (watched once it exists)
/// and every [interval].
///
/// Passes never overlap: a trigger during a pass makes one more pass after
/// it. An error a pass throws goes to the stream, and the passes go on.
/// Cancelling stops the timer and the watching, and completes once a pass
/// under way has ended.
Stream<T> follow<T>(
  String dir, {
  required bool recursive,
  required Duration interval,
  required Future<void> Function(EventSink<T> out) pass,
}) => _Follower<T>(dir, recursive, interval, pass)._controller.stream;

final class _Follower<T> {
  _Follower(this._dir, this._recursive, this._interval, this._pass) {
    _controller = StreamController<T>(onListen: _start, onCancel: _stop);
  }

  final String _dir;
  final bool _recursive;
  final Duration _interval;
  final Future<void> Function(EventSink<T> out) _pass;

  late final StreamController<T> _controller;
  Timer? _poll;
  StreamSubscription<FileSystemEvent>? _watch;

  /// The passes under way, `null` when there are none.
  Future<void>? _passes;

  /// Whether a trigger came during a pass.
  bool _again = false;

  bool _stopped = false;

  void _start() {
    _poll = Timer.periodic(_interval, (_) => _trigger());
    _trigger();
  }

  Future<void> _stop() async {
    _stopped = true;
    _poll?.cancel();
    await _watch?.cancel();
    await _passes;
  }

  void _trigger() {
    if (_stopped) return;
    if (_passes != null) {
      _again = true;
    } else {
      _passes = _run();
    }
  }

  Future<void> _run() async {
    do {
      _again = false;
      try {
        await _watchDir();
        await _pass(_controller);
      } catch (error, stack) {
        _controller.addError(error, stack);
      }
    } while (_again && !_stopped);
    _passes = null;
  }

  /// Starts watching [_dir] when it is not watched and exists.
  ///
  /// A watch that fails or ends is dropped, and the next pass watches again:
  /// in between the poll still sees every change.
  Future<void> _watchDir() async {
    if (_watch != null || !await Directory(_dir).exists() || _stopped) return;
    _watch = Directory(_dir)
        .watch(recursive: _recursive)
        .listen(
          (_) => _trigger(),
          onError: (Object _) => _unwatch(),
          onDone: _unwatch,
        );
  }

  void _unwatch() {
    final watch = _watch;
    _watch = null;
    unawaited(watch?.cancel());
  }
}
