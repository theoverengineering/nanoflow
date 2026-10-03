// Waits for the exit of the process whose pid it is given, closes the
// adapter before that exit is told and returns from main: nothing of the
// adapter may keep the program running then, and the close completes. Says
// `closed` once it has. With `--kill` it kills the process first, so that
// the exit comes in while the adapter closes.
// test/mac_processes_test.dart runs it.
import 'dart:io';

import 'package:nanoflow_process/nanoflow_process.dart';

Future<void> main(List<String> args) async {
  final pid = int.parse(args.first);
  final processes = MacProcesses();
  processes.exitOf(pid).ignore();
  if (args.contains('--kill')) {
    // The watcher waits on the kqueue by then.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    Process.killPid(pid, ProcessSignal.sigkill);
    // The watcher tells the exit meanwhile; it is handled during the close.
    sleep(const Duration(milliseconds: 100));
  }
  await processes.close();
  stdout.writeln('closed');
}
