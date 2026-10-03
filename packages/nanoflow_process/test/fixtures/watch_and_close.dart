// Waits for the exit of the process whose pid it is given, closes the
// adapter before that process is gone and returns from main: nothing of the
// adapter may keep the program running then, and the close completes. Says
// `closed` once it has. test/mac_processes_test.dart runs it.
import 'dart:io';

import 'package:nanoflow_process/nanoflow_process.dart';

Future<void> main(List<String> args) async {
  final processes = MacProcesses();
  processes.exitOf(int.parse(args.single)).ignore();
  await processes.close();
  stdout.writeln('closed');
}
