// Runs two programs with exec, each of which appends its pid to the file the
// argument names and sleeps for 100 s. test/exec_test.dart kills this
// process with SIGKILL and waits for the programs to end too.
import 'package:nanoflow/nanoflow.dart';

Future<void> main(List<String> args) async {
  await Future.wait([
    for (var i = 0; i < 2; i++)
      exec('/bin/sh', ['-c', r'echo $$ >> "$0"; exec sleep 100', args.single]),
  ]);
}
