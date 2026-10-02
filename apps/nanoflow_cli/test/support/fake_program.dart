import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A graph program for engine tests: a POSIX `sh` script in a temporary
/// directory, deleted after the test. No Dart VM starts for a step.
///
/// - `--graph` runs the shell snippet `onGraph`, which does nothing unless
///   the test gives one, then prints a description of the graph whose `file`
///   is `graph.yaml` in the directory, so the engine keeps the sessions in
///   [runsDir].
/// - `--input` runs the shell snippet `input`, which echoes stdin unless the
///   test gives another.
/// - `--call <node>` reads the first line of stdin and runs the script
///   `nodes/<node>.sh` of the directory, from the directory, with that line
///   on its stdin; the call prints what the script prints and exits with its
///   code. The end of the call's stdin stops it: the script is killed with
///   its process group, and the call exits with 143.
/// - Anything else exits with 9.
final class FakeProgram {
  /// A program of [graph], whose nodes run the scripts [nodes] by node name.
  ///
  /// With [relativeFile], the description's `file` is relative to the
  /// current directory.
  FakeProgram(
    Map<String, Object?> graph, {
    Map<String, String> nodes = const {},
    String input = 'cat',
    String onGraph = '',
    bool relativeFile = false,
  }) : dir = Directory.systemTemp.createTempSync('nanoflow_fake_').path {
    addTearDown(() => Directory(dir).deleteSync(recursive: true));
    final graphFile = p.join(dir, 'graph.yaml');
    final description = jsonEncode({
      'file': relativeFile ? p.relative(graphFile) : graphFile,
      'graph': graph,
    });
    File(path).writeAsStringSync('''
#!/bin/sh
here=\$(cd "\$(dirname "\$0")" && pwd)
case "\$1" in
--graph)
  $onGraph
  cat <<'JSON'
$description
JSON
  ;;
--input)
  $input
  ;;
--call)
  IFS= read -r line
  cd "\$here" || exit 1
  # stdin stays on fd 3 for the watcher. The shell's own stderr, with its job
  # notices, goes nowhere; the script gets the real one through fd 4.
  exec 3<&0 4>&2 2>/dev/null
  # Job control: each job below leads a process group of its own.
  set -m
  sh "nodes/\$2.sh" 2>&4 3<&- 4>&- <<EOF &
\$line
EOF
  node=\$!
  { cat <&3 >/dev/null; kill -TERM -\$node; } 4>&- &
  watcher=\$!
  wait \$node
  code=\$?
  kill -TERM -\$watcher
  exit \$code
  ;;
*)
  exit 9
  ;;
esac
''');
    final chmod = Process.runSync('chmod', ['+x', path]);
    if (chmod.exitCode != 0) throw StateError('chmod failed: ${chmod.stderr}');
    Directory(p.join(dir, 'nodes')).createSync();
    for (final MapEntry(key: node, value: script) in nodes.entries) {
      File(p.join(dir, 'nodes', '$node.sh')).writeAsStringSync('$script\n');
    }
  }

  /// The temporary directory: the program, its `nodes/`, and the files the
  /// scripts make.
  final String dir;

  /// The program file.
  String get path => p.join(dir, 'graph.sh');

  /// Where the engine keeps the sessions of the graph: `runs` next to
  /// `graph.yaml`.
  String get runsDir => p.join(dir, 'runs');
}
