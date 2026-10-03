import 'dart:async';

import 'processes.dart';

/// The [Processes] of an OS no adapter is written for: it knows no process.
///
/// [startOf] is always `null`, and [exitOf] never completes.
final class UnsupportedProcesses implements Processes {
  @override
  bool get supported => false;

  @override
  DateTime? startOf(int pid) => null;

  @override
  Future<void> exitOf(int pid) => Completer<void>().future;

  @override
  Future<void> close() async {}
}
