// Waits for the exit of the process whose pid it is given, and returns from
// main without closing the adapter: the watcher, which still waits on the
// kqueue then, may not keep the program running. Says `watching` once the
// wait is registered, `gone` once it completed.
// test/mac_processes_test.dart runs it.
import 'dart:io';

import 'package:nanoflow_process/nanoflow_process.dart';

Future<void> main(List<String> args) async {
  final exited = MacProcesses().exitOf(int.parse(args.single));
  stdout.writeln('watching');
  await exited;
  stdout.writeln('gone');
}
