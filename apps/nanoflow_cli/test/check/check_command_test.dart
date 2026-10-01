import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nanoflow_cli/nanoflow_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// What `nanoflow` did: its exit code, stdout and stderr.
typedef Outcome = ({int code, String out, String err});

/// Runs `nanoflow` with [args] and [stdin].
Future<Outcome> nanoflow(List<String> args, {String stdin = ''}) async {
  final out = _Capture();
  final err = _Capture();
  final outSink = IOSink(out);
  final errSink = IOSink(err);
  final code = await runCli(
    args,
    stdin: Stream.value(utf8.encode(stdin)),
    stdout: outSink,
    stderr: errSink,
  );
  await outSink.close();
  await errSink.close();
  return (code: code, out: out.text, err: err.text);
}

final class _Capture implements StreamConsumer<List<int>> {
  final _bytes = BytesBuilder();

  String get text => utf8.decode(_bytes.toBytes());

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach(_bytes.add);

  @override
  Future<void> close() async {}
}

/// A graph that passes check.
const validGraph = {
  'start': 'a',
  'nodes': {
    'a': {'command': 'a.sh', 'then': 'b'},
    'b': {'command': 'b.sh'},
  },
};

/// A graph with a typo and nothing else wrong.
const typoGraph = {
  'start': 'a',
  'nodes': {
    'a': {'command': 'a.sh', 'thn': 'b'},
    'b': {'command': 'b.sh'},
  },
};

/// A graph with two problems of meaning.
const unknownTargetsGraph = {
  'start': 'a',
  'nodes': {
    'a': {
      'decide': 'a.sh',
      'then': 'b',
      'else': ['c', 'c'],
    },
    'b': {'command': 'b.sh'},
  },
};

String describe(Map<String, Object?> graph) =>
    jsonEncode({'file': 'graph.yaml', 'graph': graph});

/// Writes an executable POSIX shell script with [body] and gives its path.
String script(String body) {
  final dir = Directory.systemTemp.createTempSync('nanoflow_check_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File(p.join(dir.path, 'graph.sh'))
    ..writeAsStringSync('#!/bin/sh\n$body');
  final chmod = Process.runSync('chmod', ['+x', file.path]);
  if (chmod.exitCode != 0) throw StateError('chmod failed: ${chmod.stderr}');
  return file.path;
}

/// A graph program that prints [description] for `--graph` after the
/// arguments [args], and fails with code 9 for anything else.
String describer(String description, {List<String> args = const []}) {
  final expected = [...args, '--graph'];
  final test = [
    '[ \$# -eq ${expected.length} ]',
    for (final (i, arg) in expected.indexed) '[ "\$${i + 1}" = "$arg" ]',
  ].join(' && ');
  return script('''
$test || exit 9
cat <<'JSON'
$description
JSON
''');
}

void main() {
  group('description on stdin', () {
    test('a valid graph: exit 0 and nothing printed', () async {
      final result = await nanoflow(['check'], stdin: describe(validGraph));
      expect(result, (code: 0, out: '', err: ''));
    });

    test('a structural problem: its line on stdout, exit 1', () async {
      final result = await nanoflow(['check'], stdin: describe(typoGraph));
      expect(result, (code: 1, out: 'nodes.a: unknown key "thn"\n', err: ''));
    });

    test('problems of meaning: one line each, exit 1', () async {
      final result = await nanoflow([
        'check',
      ], stdin: describe(unknownTargetsGraph));
      expect(result, (
        code: 1,
        out:
            'nodes.a.else: unknown node "c"\n'
            'nodes.a.else: "c" is listed more than once\n',
        err: '',
      ));
    });

    test('the graph of the description is what is checked', () async {
      final result = await nanoflow([
        'check',
      ], stdin: jsonEncode({'file': 'graph.yaml', 'graph': 'a'}));
      expect(result, (code: 1, out: 'graph: expected an object\n', err: ''));
    });

    test('stdin that is not JSON cannot be read', () async {
      for (final stdin in ['', 'start: a', '{"file": "graph.yaml"']) {
        final result = await nanoflow(['check'], stdin: stdin);
        expect(result, (
          code: 1,
          out: 'cannot read the graph: stdin: not JSON\n',
          err: '',
        ), reason: stdin);
      }
    });

    test('stdin that is not a description cannot be read', () async {
      for (final json in <Object?>[
        validGraph,
        {'graph': validGraph},
        {'file': 5, 'graph': validGraph},
        {'file': 'graph.yaml'},
        [validGraph],
      ]) {
        final result = await nanoflow(['check'], stdin: jsonEncode(json));
        expect(result, (
          code: 1,
          out:
              'cannot read the graph: stdin: '
              'expected {"file": <path>, "graph": <graph>}\n',
          err: '',
        ), reason: '$json');
      }
    });
  });

  group('graph program after --', () {
    test('a valid graph: exit 0 and nothing printed', () async {
      final program = describer(describe(validGraph));
      final result = await nanoflow(['check', '--', program]);
      expect(result, (code: 0, out: '', err: ''));
    });

    test('the program gets its arguments before --graph', () async {
      final program = describer(
        describe(validGraph),
        args: ['graph.yaml', '--strict'],
      );
      final result = await nanoflow([
        'check',
        '--',
        program,
        'graph.yaml',
        '--strict',
      ]);
      expect(result, (code: 0, out: '', err: ''));
    });

    test('a graph with problems: one line each, exit 1', () async {
      final typo = await nanoflow([
        'check',
        '--',
        describer(describe(typoGraph)),
      ]);
      expect(typo, (code: 1, out: 'nodes.a: unknown key "thn"\n', err: ''));
      final unknown = await nanoflow([
        'check',
        '--',
        describer(describe(unknownTargetsGraph)),
      ]);
      expect(unknown, (
        code: 1,
        out:
            'nodes.a.else: unknown node "c"\n'
            'nodes.a.else: "c" is listed more than once\n',
        err: '',
      ));
    });

    test('a program that fails: one line, its stderr passed on', () async {
      final program = script('echo "no Graph.start" >&2\nexit 3\n');
      final result = await nanoflow(['check', '--', program]);
      expect(result, (
        code: 1,
        out: 'cannot read the graph: --graph exited with code 3\n',
        err: 'no Graph.start\n',
      ));
    });

    test('a program that prints no description: one line', () async {
      final notJson = await nanoflow([
        'check',
        '--',
        script('echo "Building..."\n'),
      ]);
      expect(notJson, (
        code: 1,
        out: 'cannot read the graph: --graph output: not JSON\n',
        err: '',
      ));
      final graphOnly = await nanoflow([
        'check',
        '--',
        describer(jsonEncode(validGraph)),
      ]);
      expect(graphOnly, (
        code: 1,
        out:
            'cannot read the graph: --graph output: '
            'expected {"file": <path>, "graph": <graph>}\n',
        err: '',
      ));
    });

    test('a program that does not start: one line', () async {
      final missing = p.join(Directory.systemTemp.path, 'no-such-graph-xyz');
      final result = await nanoflow(['check', '--', missing]);
      expect(result, (
        code: 1,
        out:
            'cannot read the graph: '
            'failed to start $missing: No such file or directory\n',
        err: '',
      ));
    });
  });

  group('arguments', () {
    const usage = 'usage: nanoflow check [-- <graph program> [args...]]\n';

    test('anything else prints the usage on stderr, exit 2', () async {
      for (final args in [
        <String>[],
        ['check', 'graph.yaml'],
        ['check', '--'],
        ['check', '--graph'],
        ['chek'],
        ['--help'],
      ]) {
        final result = await nanoflow(args, stdin: describe(validGraph));
        expect(result, (code: 2, out: '', err: usage), reason: '$args');
      }
    });
  });
}
