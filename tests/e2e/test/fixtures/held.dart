// A workflow program for test/crash_resume_test.dart, which compiles it. Its
// middle step waits until there is a file `go` in the project directory, so
// that the test can kill the program while the step runs; the body of each
// step counts its runs there, in `<step>.runs`, a byte a run.
//
//   held <project dir> <change>        starts a session and prints its id
//   held <project dir> --resume <id>   takes the session on, prints its id
//
// Then it prints what the workflow returned.
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';
import 'package:path/path.dart' as p;

Future<String> held(Flow f, String change) async {
  final collected = await f.step('collect', () {
    _ran(f, 'collect');
    return '$change collected';
  });
  final inspected = await f.step('inspect', () async {
    _ran(f, 'inspect');
    while (!File(p.join(f.directory, 'go')).existsSync()) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return '$collected, inspected';
  });
  return f.step('publish', () {
    _ran(f, 'publish');
    return '$inspected, published';
  });
}

void _ran(Flow f, String step) =>
    File(p.join(f.directory, '$step.runs'))
        .writeAsStringSync('x', mode: FileMode.append);

Future<void> main(List<String> args) async {
  final flow = Flow(directory: args.first);
  final session = switch (args.sublist(1)) {
    ['--resume', final id] => await flow.resume(held, id),
    [final change] => await flow.start(held, change),
    _ => throw ArgumentError.value(args, 'args'),
  };
  print(session.id);
  print(await session.result);
}
