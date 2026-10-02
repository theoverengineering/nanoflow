// A graph program for test/resume_test.dart: its first step holds until the
// file `release` appears next to the program, so the test kills the engine
// while the step runs.
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';

/// The directory of this program: where the test watches and releases it.
final String _dir = File(Platform.script.toFilePath()).parent.path;

/// Writes the pid of its call to `call.pid` and the pid of the command it
/// runs to `command.pid`, then waits for `release`.
final hold = node((Object? _) async {
  print('holding');
  final pidFile = File('$_dir/call.pid.tmp')..writeAsStringSync('$pid');
  pidFile.renameSync('$_dir/call.pid');
  await exec('sh', [
    '-c',
    r'echo $$ > "$1/command.pid.tmp" && mv "$1/command.pid.tmp" "$1/command.pid"'
        '\n'
        r'until [ -e "$1/release" ]; do sleep 0.05; done',
    'sh',
    _dir,
  ]);
});

final done = node((Object? _) async => print('released'));

final graph = Graph.start(hold).next(done);

void main(List<String> args) => serve(args, graph);
