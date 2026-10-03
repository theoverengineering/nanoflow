// Runs `echo ran` with exec through the shell its argument names, and prints
// what it gave or why it would not run it. test/exec_test.dart starts it
// without a controlling terminal.
import 'dart:io';

import 'package:nanoflow/src/exec.dart';

Future<void> main(List<String> args) async {
  try {
    stdout.write(await execIn(args.single, 'echo', ['ran']));
  } on StateError catch (e) {
    print(e.message);
  }
}
