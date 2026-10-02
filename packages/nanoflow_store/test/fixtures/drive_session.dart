// Creates a session in the runs directory its argument names, prints the
// session's id and holds the session, as an engine that drives it does, until
// it is killed. test/fs_store_test.dart runs it.
import 'dart:io';

import 'package:nanoflow_store/nanoflow_store.dart';

Future<void> main(List<String> args) async {
  final session = await FsStore(args.single).createSession(
    graphName: 'review',
    graph: const {
      'start': 'collect',
      'nodes': {
        'collect': {'command': 'collect.sh'},
      },
    },
    startNodes: const [(node: 'collect', takesInput: false)],
  );
  print(session.session.id);
  await stdin.drain<void>();
}
