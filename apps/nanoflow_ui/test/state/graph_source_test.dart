import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/platform/shell.dart';
import 'package:nanoflow_ui/state/graph_source.dart';
import 'package:path/path.dart' as p;

/// A graph description whose graph has the nodes [nodes], each ending the
/// run.
String _description(String file, List<String> nodes) => jsonEncode({
  'file': file,
  'graph': {
    'start': nodes.first,
    'nodes': {
      for (final node in nodes) node: {'command': 'nodes/$node/run.sh'},
    },
  },
});

/// `nanoflow-yaml <file> --graph --watch`: prints the lines of the file
/// `lines` next to it as they are written, and its pid to `pid`.
const _yamlWatch = r'''
[ "$#" = 3 ] && [ "$2" = --graph ] && [ "$3" = --watch ] || exit 64
echo $$ > "$(dirname "$0")/pid"
exec tail -n +1 -f "$(dirname "$0")/lines"
''';

/// `nanoflow check`: rejects a description with a node called `broken`.
const _nanoflowCheck = r'''
[ "$#" = 1 ] && [ "$1" = check ] || exit 64
line=$(cat)
case "$line" in
  *'"broken"'*)
    echo 'nodes.broken.then: names no node "nowhere"'
    echo 'nodes.x: cannot be reached from start'
    exit 1;;
esac
exit 0
''';

void main() {
  late Directory tmp;
  late String bin;
  late String graphFile;
  late File lines;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nanoflow_graph_source_test');
    bin = p.join(tmp.path, 'bin');
    Directory(bin).createSync();
    graphFile = p.join(tmp.path, 'review.yaml');
    File(graphFile).writeAsStringSync('start: collect\n');
    lines = File(p.join(bin, 'lines'))..writeAsStringSync('');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Puts an executable [name] running [body] on the test's PATH.
  void program(String name, String body) {
    final file = File(p.join(bin, name))..writeAsStringSync('#!/bin/sh\n$body');
    Process.runSync('chmod', ['+x', file.path]);
  }

  void printLine(String line) =>
      lines.writeAsStringSync('$line\n', mode: FileMode.append);

  GraphSource source() {
    final source = GraphSource(
      file: graphFile,
      shell: Shell(environment: {'PATH': '$bin:/usr/bin:/bin'}),
      fileCheckInterval: const Duration(milliseconds: 20),
    );
    addTearDown(source.dispose);
    return source;
  }

  /// Waits until [done] holds for [source].
  Future<void> until(GraphSource source, bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) {
        fail(
          'waited too long: graph ${source.graph?.nodes.keys}, '
          'errors ${source.errors}, problem ${source.programProblem}, '
          'check ${source.checkProblem}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test(
    'shows the graph nanoflow-yaml prints once nanoflow check passes it',
    () async {
      program('nanoflow-yaml', _yamlWatch);
      program('nanoflow', _nanoflowCheck);
      printLine(_description(graphFile, ['collect', 'notify']));
      final graph = source();
      var notified = 0;
      graph.addListener(() => notified++);
      await graph.start();

      await until(graph, () => graph.graph != null);
      expect(graph.graph!.nodes.keys, ['collect', 'notify']);
      expect(graph.errors, isEmpty);
      expect(graph.programProblem, isNull);
      expect(graph.checkProblem, isNull);
      expect(notified, greaterThan(0));
    },
  );

  test(
    'lists the errors check finds and keeps the last graph that passed',
    () async {
      program('nanoflow-yaml', _yamlWatch);
      program('nanoflow', _nanoflowCheck);
      printLine(_description(graphFile, ['collect']));
      final graph = source();
      await graph.start();
      await until(graph, () => graph.graph != null);

      printLine(_description(graphFile, ['collect', 'broken']));
      await until(graph, () => graph.errors.isNotEmpty);
      expect(graph.errors, [
        'nodes.broken.then: names no node "nowhere"',
        'nodes.x: cannot be reached from start',
      ]);
      expect(graph.graph!.nodes.keys, ['collect']);

      printLine(_description(graphFile, ['collect', 'notify']));
      await until(graph, () => graph.errors.isEmpty);
      expect(graph.graph!.nodes.keys, ['collect', 'notify']);
    },
  );

  test(
    'has no valid graph yet while no description has passed check',
    () async {
      program('nanoflow-yaml', _yamlWatch);
      program('nanoflow', _nanoflowCheck);
      printLine(_description(graphFile, ['broken']));
      final graph = source();
      await graph.start();
      await until(graph, () => graph.errors.isNotEmpty);
      expect(graph.graph, isNull);
      expect(noValidGraphYet, 'No valid graph yet');
    },
  );

  test('ignores a line that is not a description', () async {
    program('nanoflow-yaml', _yamlWatch);
    program('nanoflow', _nanoflowCheck);
    printLine('Compiling graph.dart...');
    printLine('[1, 2]');
    printLine(_description(graphFile, ['collect']));
    final graph = source();
    await graph.start();
    await until(graph, () => graph.graph != null);
    expect(graph.errors, isEmpty);
  });

  test('says when check passes a graph the app cannot read', () async {
    program('nanoflow-yaml', _yamlWatch);
    program('nanoflow', _nanoflowCheck);
    printLine(
      jsonEncode({
        'file': graphFile,
        'graph': {'start': 'collect'},
      }),
    );
    final graph = source();
    await graph.start();
    await until(graph, () => graph.errors.isNotEmpty);
    expect(graph.errors, ['graph.nodes: missing']);
    expect(graph.graph, isNull);
  });

  test('says check failed when it names no error', () async {
    program('nanoflow-yaml', _yamlWatch);
    program('nanoflow', 'echo "unexpected: crash" >&2; exit 70');
    printLine(_description(graphFile, ['collect']));
    final graph = source();
    await graph.start();
    await until(graph, () => graph.errors.isNotEmpty);
    expect(graph.errors, [
      'nanoflow check exited with code 70: unexpected: crash',
    ]);
  });

  test('says nanoflow-yaml is not on the PATH', () async {
    program('nanoflow', _nanoflowCheck);
    final graph = source();
    await graph.start();
    expect(graph.programProblem!.message, 'nanoflow-yaml not found on PATH');
    expect(graph.graph, isNull);
  });

  test(
    'without nanoflow on the PATH shows the graph unchecked and says so',
    () async {
      program('nanoflow-yaml', _yamlWatch);
      printLine(_description(graphFile, ['collect', 'broken']));
      final graph = source();
      await graph.start();
      await until(graph, () => graph.graph != null);
      expect(
        graph.checkProblem,
        'nanoflow not found on PATH — graph not checked',
      );
      expect(graph.errors, isEmpty);
      expect(graph.graph!.nodes.keys, ['collect', 'broken']);
    },
  );

  test(
    'says nanoflow-yaml exited, with its code and the end of its stderr',
    () async {
      program('nanoflow-yaml', '''
echo '${_description(graphFile, ['collect'])}'
i=0
while [ \$i -lt 30 ]; do echo "line \$i" >&2; i=\$((i + 1)); done
echo 'review.yaml: cannot be read' >&2
exit 3
''');
      program('nanoflow', _nanoflowCheck);
      final graph = source();
      await graph.start();
      await until(graph, () => graph.programProblem != null);
      expect(graph.programProblem!.message, 'nanoflow-yaml exited with code 3');
      final details = graph.programProblem!.details.split('\n');
      expect(details.last, 'review.yaml: cannot be read');
      expect(details, hasLength(GraphSource.stderrLines));
      await until(graph, () => graph.graph != null);
    },
  );

  test(
    'says the file is unavailable while it is gone, and keeps the graph',
    () async {
      program('nanoflow-yaml', _yamlWatch);
      program('nanoflow', _nanoflowCheck);
      printLine(_description(graphFile, ['collect']));
      final graph = source();
      await graph.start();
      await until(graph, () => graph.graph != null);
      expect(graph.fileMissing, isFalse);

      File(graphFile).deleteSync();
      await until(graph, () => graph.fileMissing);
      expect(graph.graph!.nodes.keys, ['collect']);
      expect(fileUnavailable, 'File unavailable');

      File(graphFile).writeAsStringSync('start: collect\n');
      await until(graph, () => !graph.fileMissing);
    },
  );

  test('dispose stops nanoflow-yaml', () async {
    program('nanoflow-yaml', _yamlWatch);
    program('nanoflow', _nanoflowCheck);
    final graph = GraphSource(
      file: graphFile,
      shell: Shell(environment: {'PATH': '$bin:/usr/bin:/bin'}),
    );
    await graph.start();
    final pidFile = File(p.join(bin, 'pid'));
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!pidFile.existsSync() || pidFile.readAsStringSync().isEmpty) {
      if (DateTime.now().isAfter(deadline)) fail('nanoflow-yaml did not start');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final pid = pidFile.readAsStringSync().trim();
    graph.dispose();
    while (Process.runSync('kill', ['-0', pid]).exitCode == 0) {
      if (DateTime.now().isAfter(deadline)) fail('nanoflow-yaml still runs');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
}
