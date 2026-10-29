// A graph program for test/crash_resume_test.dart, which compiles it. Its
// middle node waits until there is a file `go` in the project directory, so
// that the test can kill the program while the node runs; the body of each
// node counts its runs there, in `<node>.runs`, a byte a run.
//
//   held <project dir> <change>        starts a session and prints its id
//   held <project dir> --resume <id>   takes the session on, prints its id
//
// Then it prints what the graph returned.
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';
import 'package:path/path.dart' as p;

/// The project directory.
late final String work;

/// Gives what the change is collected as.
final collect = node('collect', (String change) {
  _ran('collect');
  return '$change collected';
});

/// Waits for `go` in the work directory, then inspects.
final inspect = node('inspect', (String collected) async {
  _ran('inspect');
  while (!File(p.join(work, 'go')).existsSync()) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return '$collected, inspected';
});

/// Publishes what was inspected.
final publish = node('publish', (String inspected) {
  _ran('publish');
  return '$inspected, published';
});

final held = Graph<String, String>('held', [
  Graph.start(collect).next((collected) => inspect(collected)),
  Graph.part(inspect).next((inspected) => publish(inspected)),
]);

void _ran(String node) =>
    File(p.join(work, '$node.runs'))
        .writeAsStringSync('x', mode: FileMode.append);

Future<void> main(List<String> args) async {
  work = args.first;
  final flow = Flow(directory: work);
  final session = switch (args.sublist(1)) {
    ['--resume', final id] => await flow.resume(held, id),
    [final change] => await flow.start(held, change),
    _ => throw ArgumentError.value(args, 'args'),
  };
  print(session.id);
  print(await session.result);
}
