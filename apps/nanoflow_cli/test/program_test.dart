import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_cli/nanoflow_cli.dart';
import 'package:test/test.dart';

import 'support/helpers.dart';

/// A graph program that answers `--graph` with a description of [graph].
String describer(Map<String, Object?> graph) => script('''
[ "\$1" = "--graph" ] || exit 9
cat <<'JSON'
${jsonEncode({'file': 'graph.yaml', 'graph': graph})}
JSON
''');

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
      final err = Capture();
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

    test('a rejection without a reason throws the exit code', () {
      final program = GraphProgram([script('exit 5\n')]);
      expect(
        program.validateInput('{}'),
        throwsA(
          isA<GraphProgramException>().having(
            (e) => e.message,
            'message',
            '--input exited with code 5',
          ),
        ),
      );
    });

    test('a program that prints no JSON throws', () {
      final program = GraphProgram([script('echo "Checking..."\n')]);
      expect(
        program.validateInput('{}'),
        throwsA(
          isA<GraphProgramException>().having(
            (e) => e.message,
            'message',
            '--input output: not JSON',
          ),
        ),
      );
    });

    test('a program that exits without reading its stdin is no '
        'failure', () async {
      final program = GraphProgram([script('echo null\n')]);
      // More than a pipe holds: writing it fails once the program is gone.
      final raw = jsonEncode({'text': 'x' * (1 << 20)});
      expect(await program.validateInput(raw), 'null');
      // The broken pipe is found out after the program has exited.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
  });

  group('graphFile', () {
    test('gives the file of the description without checking the '
        'graph', () async {
      final program = GraphProgram([
        describer({
          'start': 'a',
          'nodes': {
            'a': {'command': 'a.sh', 'then': 'b'},
          },
        }),
      ]);
      expect(await program.graphFile(), 'graph.yaml');
    });

    test('a program that fails throws', () {
      final program = GraphProgram([
        script('exit 4\n'),
      ], stderr: IOSink(Capture()));
      expect(
        program.graphFile(),
        throwsA(
          isA<GraphProgramException>().having(
            (e) => e.message,
            'message',
            '--graph exited with code 4',
          ),
        ),
      );
    });

    test('a program that prints no description throws', () {
      final program = GraphProgram([script('echo \'{"graph": {}}\'\n')]);
      expect(
        program.graphFile(),
        throwsA(
          isA<GraphProgramException>().having(
            (e) => e.message,
            'message',
            '--graph output: expected {"file": <path>, "graph": <graph>}',
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
