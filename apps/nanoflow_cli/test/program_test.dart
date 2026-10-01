import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nanoflow_cli/nanoflow_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Writes an executable POSIX shell script with [body] and gives its path.
String script(String body) {
  final dir = Directory.systemTemp.createTempSync('nanoflow_program_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File(p.join(dir.path, 'graph.sh'))
    ..writeAsStringSync('#!/bin/sh\n$body');
  final chmod = Process.runSync('chmod', ['+x', file.path]);
  if (chmod.exitCode != 0) throw StateError('chmod failed: ${chmod.stderr}');
  return file.path;
}

/// A graph program that answers `--graph` with a description of [graph].
String describer(Map<String, Object?> graph) => script('''
[ "\$1" = "--graph" ] || exit 9
cat <<'JSON'
${jsonEncode({'file': 'graph.yaml', 'graph': graph})}
JSON
''');

final class _Capture implements StreamConsumer<List<int>> {
  final _bytes = BytesBuilder();

  String get text => utf8.decode(_bytes.toBytes());

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach(_bytes.add);

  @override
  Future<void> close() async {}
}

void main() {
  test('a program is a command, not nothing', () {
    expect(() => GraphProgram([]), throwsArgumentError);
  });

  group('describe', () {
    test('reads the description the program prints for --graph', () async {
      final program = GraphProgram([
        describer({
          'start': 'a',
          'nodes': {
            'a': {'command': 'a.sh'},
          },
        }),
      ]);
      final description = await program.describe();
      expect(description.file, 'graph.yaml');
      expect(description.graph.start.names, ['a']);
      expect(description.graph.nodes.keys, ['a']);
    });

    test('runs the command with its arguments before --graph', () async {
      final program = script('''
[ "\$1" = "graph.yaml" ] && [ "\$2" = "--graph" ] || exit 9
echo '{"file": "graph.yaml", "graph": {"start": "a", "nodes": {"a": {"command": "a.sh"}}}}'
''');
      final description = await GraphProgram([program, 'graph.yaml'])
          .describe();
      expect(description.graph.nodes.keys, ['a']);
    });

    test('a graph that does not pass check throws its errors', () {
      final program = GraphProgram([
        describer({
          'start': 'a',
          'nodes': {
            'a': {'command': 'a.sh', 'then': 'b'},
          },
        }),
      ]);
      expect(
        program.describe(),
        throwsA(
          isA<GraphCheckException>().having((e) => e.errors, 'errors', [
            'nodes.a.then: unknown node "b"',
          ]),
        ),
      );
    });

    test('a program that fails: its stderr goes to stderr', () async {
      final err = _Capture();
      final sink = IOSink(err);
      final program = GraphProgram([
        script('echo oops >&2\nexit 4\n'),
      ], stderr: sink);
      await expectLater(
        program.describe(),
        throwsA(
          isA<GraphProgramException>().having(
            (e) => e.message,
            'message',
            '--graph exited with code 4',
          ),
        ),
      );
      await sink.close();
      expect(err.text, 'oops\n');
    });
  });

  group('validateInput', () {
    test('gives the JSON the program prints for --input', () async {
      final program = GraphProgram([
        script('''
[ "\$1" = "--input" ] || exit 9
read -r line
printf '{"checked": %s}\\n' "\$line"
'''),
      ]);
      expect(await program.validateInput('"main"\n'), '{"checked": "main"}');
    });

    test('a rejected input throws the program stderr', () {
      final program = GraphProgram([
        script('echo "branch: missing" >&2\nexit 1\n'),
      ]);
      expect(
        program.validateInput('{}'),
        throwsA(
          isA<GraphProgramException>().having(
            (e) => e.message,
            'message',
            'branch: missing',
          ),
        ),
      );
    });
  });

  group('startCall', () {
    test('starts --call for the node; the caller owns its streams', () async {
      final program = GraphProgram([
        script('''
[ "\$1" = "--call" ] || exit 9
read -r line
echo "\$2 got \$line"
'''),
      ]);
      final call = await program.startCall('inspect');
      final out = utf8.decodeStream(call.stdout);
      final err = utf8.decodeStream(call.stderr);
      call.stdin.writeln('{"id": "1"}');
      await call.stdin.close();
      expect(await call.exitCode, 0);
      expect(await out, 'inspect got {"id": "1"}\n');
      expect(await err, '');
    });
  });
}
