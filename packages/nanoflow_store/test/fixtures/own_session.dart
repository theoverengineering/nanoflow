// Creates a session in the runs directory its argument names, prints the
// session's id and owns the session, as the process that runs it does, until
// it is killed. test/fs_store_test.dart runs it.
import 'dart:io';

import 'package:nanoflow_store/nanoflow_store.dart';

Future<void> main(List<String> args) async {
  final session = await FsStore(args.single)
      .createSession(workflow: 'review', graph: null, input: null, code: null);
  print(session.session.id);
  await stdin.drain<void>();
}
