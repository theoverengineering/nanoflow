// Runs `cat` with exec through the shell its argument names, with `piped` on
// its stdin, and prints what it gave or why it would not run it.
// test/exec_test.dart starts it without a controlling terminal.
import 'package:nanoflow/src/exec.dart';

Future<void> main(List<String> args) async {
  try {
    print(await execIn(args.single, 'cat', [], stdin: 'piped'));
  } on StateError catch (e) {
    print(e.message);
  }
}
