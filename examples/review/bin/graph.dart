// Reviews a branch as a nanoflow session of the review graph, in runs/ of
// this package — or of the directory of the binary, once compiled — and
// prints the session's id:
//
//   dart run bin/graph.dart parseConfig
//   dart run bin/graph.dart --resume <id>    # takes a session on
//
// Ctrl+C stops the session, which --resume can take on later: exit code 130.
// Any other failure is printed on stderr: exit code 1.
import 'dart:async';
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';
import 'package:review_example/review_graph.dart';

const _usage = '''
Usage: graph <branch>
       graph --resume <session id>''';

Future<void> main(List<String> args) async {
  final flow = Flow()
    ..addCodec(Change.fromJson)
    ..addCodec(Report.fromJson)
    ..addCodec(Collected.fromJson);
  final interrupt = ProcessSignal.sigint.watch().listen((_) => flow.stop());
  try {
    final session = switch (args) {
      ['--resume', final id] => await flow.resume(reviewGraph.run, id),
      [final branch] when !branch.startsWith('-') => await flow.start(
        reviewGraph.run,
        branch,
      ),
      _ => null,
    };
    if (session == null) {
      stderr.writeln(_usage);
      exitCode = 2;
      return;
    }
    print(session.id);
    await session.result;
  } on FlowStoppedException {
    exitCode = 130;
  } on Exception catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  } finally {
    await interrupt.cancel();
  }
}
