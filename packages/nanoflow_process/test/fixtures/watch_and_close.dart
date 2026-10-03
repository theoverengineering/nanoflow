// Waits for the exit of a child process, closes the adapter before the child
// is gone and returns from main: nothing of the adapter may keep the process
// running then. test/mac_processes_test.dart runs it.
import 'dart:io';

import 'package:nanoflow_process/nanoflow_process.dart';

Future<void> main() async {
  final processes = MacProcesses();
  final child = await Process.start('sleep', ['30']);
  processes.exitOf(child.pid).ignore();
  await processes.close();
  child.kill(ProcessSignal.sigkill);
  await child.exitCode;
}
