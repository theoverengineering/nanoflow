import 'dart:io' as io;

import 'check/check_command.dart';

const _usage = 'usage: nanoflow check [-- <graph program> [args...]]';

/// Runs the `nanoflow` command with [args] and gives its exit code.
///
/// [stdin], [stdout] and [stderr] are those of this process unless given.
/// Arguments that are not a command print the usage on [stderr]; the exit
/// code is 2.
Future<int> runCli(
  List<String> args, {
  Stream<List<int>>? stdin,
  io.IOSink? stdout,
  io.IOSink? stderr,
}) async {
  final input = stdin ?? io.stdin;
  final output = stdout ?? io.stdout;
  final errors = stderr ?? io.stderr;
  switch (args) {
    case ['check']:
      return runCheck(null, stdin: input, stdout: output, stderr: errors);
    case ['check', '--', _, ...]:
      return runCheck(
        args.sublist(2),
        stdin: input,
        stdout: output,
        stderr: errors,
      );
  }
  errors.writeln(_usage);
  return 2;
}
