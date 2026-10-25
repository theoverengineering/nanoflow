// A workflow program on the storage at a place, for test/contract_test.dart.
// Its middle effect waits until there is a file `go` in the work directory,
// so that the test can kill the program while the effect runs; the body of
// each effect counts its runs there, in `<effect>.runs`, a byte a run.
//
//   held <place> <work dir> <change>        starts a session, prints its id
//   held <place> <work dir> --resume <id>   takes the session on, prints its id
//
// Then it prints what the workflow returned.
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';
import 'package:path/path.dart' as p;

import '../support/places.dart';

/// The work directory.
late final String work;

Future<String> held(Flow f, String change) async {
  final collected = await f.effect('collect', () {
    _ran('collect');
    return '$change collected';
  });
  final inspected = await f.effect('inspect', () async {
    _ran('inspect');
    while (!File(p.join(work, 'go')).existsSync()) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return '$collected, inspected';
  });
  return f.effect('publish', () {
    _ran('publish');
    return '$inspected, published';
  });
}

void _ran(String effect) =>
    File(p.join(work, '$effect.runs'))
        .writeAsStringSync('x', mode: FileMode.append);

Future<void> main(List<String> args) async {
  work = args[1];
  final flow = Flow(directory: work, store: storeAt(args[0]));
  final session = switch (args.sublist(2)) {
    ['--resume', final id] => await flow.resume(held, id),
    [final change] => await flow.start(held, change),
    _ => throw ArgumentError.value(args, 'args'),
  };
  print(session.id);
  print(await session.result);
}
