import 'dart:async';

import 'processes.dart';

/// [Processes] for tests: a test starts and ends the processes by hand.
///
/// When not [supported], it behaves as an adapter that cannot tell:
/// [startOf] is `null` and [exitOf] never completes, whatever was started.
final class FakeProcesses implements Processes {
  FakeProcesses({this.supported = true});

  @override
  final bool supported;

  /// The processes running, by pid: their start, and their exit to come.
  final _running = <int, ({DateTime started, Completer<void> exited})>{};

  bool _closed = false;

  /// Makes the process [pid], started at [started], running.
  ///
  /// Throws a [StateError] when [pid] is running already: the OS gives a pid
  /// to a new process only once the old one is gone.
  void start(int pid, DateTime started) {
    if (_running.containsKey(pid)) {
      throw StateError('The process $pid is running already');
    }
    _running[pid] = (started: started, exited: Completer<void>());
  }

  /// Ends the process [pid]: its [exitOf] futures complete, unless [close]
  /// was called, and [startOf] is `null` for it. Does nothing when [pid] is
  /// not running.
  void exit(int pid) {
    final process = _running.remove(pid);
    if (process != null && !_closed) process.exited.complete();
  }

  @override
  DateTime? startOf(int pid) => supported ? _running[pid]?.started : null;

  @override
  Future<void> exitOf(int pid) {
    if (!supported || _closed) return Completer<void>().future;
    return _running[pid]?.exited.future ?? Future.value();
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}
