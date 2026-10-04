// A workflow program for test/crash_resume_test.dart, which compiles it. Its
// middle effect waits until there is a file `go` in the project directory, so
// that the test can kill the program while the effect runs; the body of each
// effect counts its runs there, in `<effect>.runs`, a byte a run.
//
//   held <project dir> <change>        starts a session and prints its id
//   held <project dir> --resume <id>   takes the session on, prints its id
//
// Then it prints what the workflow returned.
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';
import 'package:path/path.dart' as p;

Future<String> held(Flow f, String change) async {
  final collected = await f.effect('collect', () {
    _ran(f, 'collect');
    return '$change collected';
  });
  final inspected = await f.effect('inspect', () async {
    _ran(f, 'inspect');
    while (!File(p.join(f.directory, 'go')).existsSync()) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return '$collected, inspected';
  });
  return f.effect('publish', () {
    _ran(f, 'publish');
    return '$inspected, published';
  });
}

void _ran(Flow f, String effect) =>
    File(p.join(f.directory, '$effect.runs'))
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
