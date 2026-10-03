// The macOS adapter of the OS port (design §3), through FFI to libc: the
// start of a process from `sysctl`, its exit from a kqueue that one
// background isolate waits on.

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'processes.dart';

/// The [Processes] of macOS.
///
/// [startOf] reads the process's `kinfo_proc` with `sysctl`. [exitOf]
/// registers the pid with a kqueue (`EVFILT_PROC`, `NOTE_EXIT`) in the
/// calling isolate; one background isolate, started by the first [exitOf],
/// waits on the kqueue and sends back the pids that exited. [close] wakes it
/// with an `EVFILT_USER` event, waits for it to end and closes the kqueue.
///
/// Once [exitOf] was called, the program does not end until [close]: the
/// background isolate waits in a blocking call.
final class MacProcesses implements Processes {
  /// The kqueue, made by the first [exitOf].
  int? _kq;

  /// The port the watcher isolate sends the pids that exited to.
  RawReceivePort? _exits;

  /// The watcher isolate, once spawned.
  Isolate? _watcher;

  /// Completes when the watcher isolate has ended, or failed to start.
  Future<void>? _watcherEnded;

  /// Why the watcher stopped, or did not start, before [close]: the waits,
  /// and later [exitOf], fail with it.
  Object? _failure;

  /// The waits for the pids registered with the kqueue that have not exited
  /// yet: every [exitOf] of a pid shares one registration.
  final _waits = <int, Completer<void>>{};

  /// What [close] gives, once called.
  Future<void>? _closed;

  @override
  bool get supported => true;

  @override
  DateTime? startOf(int pid) => using((arena) {
    final name = arena<Int>(4);
    name[0] = _ctlKern;
    name[1] = _kernProc;
    name[2] = _kernProcPid;
    name[3] = pid;
    final info = arena<Uint8>(_kinfoProcSize);
    final size = arena<Size>()..value = _kinfoProcSize;
    final failed = _sysctl(name, 4, info.cast(), size, nullptr, 0) != 0;
    // Nothing written when there is no such process.
    if (failed || size.value == 0) return null;
    // `kp_proc.p_un.__p_starttime`, at the start of `kinfo_proc`.
    final start = info.cast<_Timeval>().ref;
    return timeOfTimeval(start.seconds, start.microseconds);
  });

  /// Completes when the process [pid] is gone: at once when it is gone
  /// already.
  ///
  /// Completes with an [OSError] when the OS refuses to watch the process
  /// for another reason than its absence, or when the watcher isolate
  /// stopped.
  @override
  Future<void> exitOf(int pid) async {
    if (_closed != null) return Completer<void>().future;
    if (_failure case final failure?) throw failure;
    if (_waits[pid] case final wait?) return wait.future;
    final error = _change(
      _kq ??= _watch(),
      ident: pid,
      filter: _evfiltProc,
      flags: _evAdd | _evOneshot,
      fflags: _noteExit,
    );
    switch (error) {
      case 0:
        return (_waits[pid] = Completer<void>()).future;
      case _esrch:
        return;
      default:
        throw OSError('Cannot watch the exit of the process $pid', error);
    }
  }

  @override
  Future<void> close() => _closed ??= _close();

  Future<void> _close() async {
    _waits.clear();
    final kq = _kq;
    if (kq == null) return;
    final woken = _wake(kq);
    if (!woken) {
      // The watcher waits on in `kevent`, where a kill does not reach it.
      // Closing the kqueue ends that wait, and the kill, or the kqueue that
      // now fails, ends the watcher before it waits again.
      _watcher?.kill(priority: Isolate.immediate);
      _closeFd(kq);
    }
    await _watcherEnded;
    _exits!.close();
    if (woken) _closeFd(kq);
  }

  /// Makes the kqueue, with the event that wakes the watcher, and starts the
  /// watcher isolate on it.
  int _watch() {
    final kq = _kqueue();
    if (kq == -1) throw const OSError('Cannot make a kqueue');
    try {
      final error = _change(
        kq,
        ident: _wakeIdent,
        filter: _evfiltUser,
        flags: _evAdd | _evClear,
      );
      if (error != 0) {
        throw OSError('Cannot add the wake event to a kqueue', error);
      }
    } catch (_) {
      _closeFd(kq);
      rethrow;
    }
    final exits = _exits = RawReceivePort(_exited, 'nanoflow_process exits');
    _watcherEnded = _runWatcher(kq, exits.sendPort);
    return kq;
  }

  /// Runs the watcher isolate on [kq] until it ends. When it ends before
  /// [close], or does not start, the waits fail.
  Future<void> _runWatcher(int kq, SendPort exits) async {
    final ended = ReceivePort('nanoflow_process watcher ended');
    try {
      _watcher = await Isolate.spawn(
        _watchExits,
        (kq, exits),
        onExit: ended.sendPort,
        debugName: 'nanoflow_process watcher',
      );
    } catch (e) {
      ended.close();
      _fail(e);
      return;
    }
    await ended.first;
    if (_closed == null) _fail(const OSError('Stopped watching for exits'));
  }

  /// Wakes the watcher to end; `false` when the kqueue refused.
  bool _wake(int kq) {
    try {
      final error = _change(
        kq,
        ident: _wakeIdent,
        filter: _evfiltUser,
        flags: 0,
        fflags: _noteTrigger,
      );
      return error == 0;
    } on OSError {
      return false;
    }
  }

  void _fail(Object failure) {
    _failure = failure;
    final waits = [..._waits.values];
    _waits.clear();
    for (final wait in waits) {
      wait.completeError(failure);
    }
  }

  void _exited(Object? pid) => _waits.remove(pid)?.complete();
}

/// The time a `struct timeval` of [seconds] and [microseconds] holds, in
/// UTC, truncated to milliseconds: the microseconds are dropped, never
/// rounded.
DateTime timeOfTimeval(int seconds, int microseconds) =>
    DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000 + microseconds ~/ 1000,
      isUtc: true,
    );

/// The watcher isolate: waits on the kqueue and sends the pid of every
/// process that exits to the port, until the wake event comes or the kqueue
/// fails.
void _watchExits((int, SendPort) args) {
  final (kq, exits) = args;
  final events = calloc<_KEvent>(_eventsAtOnce);
  final noWait = calloc<_Timespec>();
  try {
    while (true) {
      // Blocks until events come.
      var count = _kevent(kq, nullptr, 0, events, _eventsAtOnce, nullptr);
      if (count == -1) {
        // A signal that reaches this thread, as the SIGCHLD of a child
        // process does, fails the wait with EINTR, and then it waits again.
        // A call that does not wait cannot be interrupted: when it fails
        // too, the kqueue is unusable, as when it was closed, and the
        // watcher ends.
        count = _kevent(kq, nullptr, 0, events, _eventsAtOnce, noWait);
        if (count == -1) return;
      }
      for (var i = 0; i < count; i++) {
        final event = events[i];
        switch (event.filter) {
          case _evfiltUser:
            return;
          case _evfiltProc:
            exits.send(event.ident);
        }
      }
    }
  } finally {
    calloc
      ..free(events)
      ..free(noWait);
  }
}

/// Applies a change to the kqueue [kq] without waiting for events, and gives
/// the error of the change: 0 when there is none.
int _change(
  int kq, {
  required int ident,
  required int filter,
  required int flags,
  int fflags = 0,
}) => using((arena) {
  final change = arena<_KEvent>();
  change.ref
    ..ident = ident
    ..filter = filter
    // With a receipt, the change's error comes back as an event, not as the
    // error of the call.
    ..flags = flags | _evReceipt
    ..fflags = fflags;
  final receipt = arena<_KEvent>();
  // Zero: do not wait.
  final timeout = arena<_Timespec>();
  if (_kevent(kq, change, 1, receipt, 1, timeout) != 1) {
    throw const OSError('Cannot change a kqueue');
  }
  return receipt.ref.data;
});

// The values of the macOS headers this adapter uses.
const _ctlKern = 1;
const _kernProc = 14;
const _kernProcPid = 1;

/// `sizeof(struct kinfo_proc)` on 64-bit macOS.
const _kinfoProcSize = 648;

const _evfiltProc = -5;
const _evfiltUser = -10;
const _evAdd = 0x1;
const _evOneshot = 0x10;
const _evClear = 0x20;
const _evReceipt = 0x40;
const _noteExit = 0x80000000;
const _noteTrigger = 0x01000000;
const _esrch = 3;

/// The ident of the `EVFILT_USER` event that wakes the watcher to end.
const _wakeIdent = 1;

/// How many events the watcher takes from the kqueue at once.
const _eventsAtOnce = 16;

/// `struct kevent` of 64-bit macOS.
final class _KEvent extends Struct {
  @UintPtr()
  external int ident;

  @Int16()
  external int filter;

  @Uint16()
  external int flags;

  @Uint32()
  external int fflags;

  @IntPtr()
  external int data;

  external Pointer<Void> udata;
}

/// `struct timespec`.
final class _Timespec extends Struct {
  @Long()
  external int seconds;

  @Long()
  external int nanoseconds;
}

/// `struct timeval` of 64-bit macOS.
final class _Timeval extends Struct {
  @Long()
  external int seconds;

  @Int32()
  external int microseconds;
}

final _libc = DynamicLibrary.process();

final _sysctl = _libc
    .lookupFunction<
      Int Function(
        Pointer<Int>,
        UnsignedInt,
        Pointer<Void>,
        Pointer<Size>,
        Pointer<Void>,
        Size,
      ),
      int Function(
        Pointer<Int>,
        int,
        Pointer<Void>,
        Pointer<Size>,
        Pointer<Void>,
        int,
      )
    >('sysctl');

final _kqueue = _libc.lookupFunction<Int Function(), int Function()>('kqueue');

final _kevent = _libc
    .lookupFunction<
      Int Function(
        Int,
        Pointer<_KEvent>,
        Int,
        Pointer<_KEvent>,
        Int,
        Pointer<_Timespec>,
      ),
      int Function(
        int,
        Pointer<_KEvent>,
        int,
        Pointer<_KEvent>,
        int,
        Pointer<_Timespec>,
      )
    >('kevent');

final _closeFd = _libc.lookupFunction<Int Function(Int), int Function(int)>(
  'close',
);
