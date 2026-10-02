@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/engine.dart';

void main() {
  setUpAll(compileEngine);

  final example = p.join(repoRoot, 'examples', 'review');

  /// A copy of the example: its graph program and its input.
  String copyExample() => copyToTemp([
    p.join(example, 'graph.dart'),
    p.join(example, 'input.json'),
  ]);

  test('nanoflow check passes the graph of the example', () async {
    final dir = copyExample();
    final result = await nanoflow([
      'check',
      '--',
      ...dartRun('graph.dart'),
    ], dir: dir);
    expect(result.code, 0, reason: '${result.out}${result.err}');
    expect(result.out, isEmpty);
  });

  test('nanoflow run drives the example to its end: inspect finds a '
      'problem, fix fixes it, and the accepted change splits into publish '
      'and notify', () async {
    final dir = copyExample();
    final result = await nanoflow(
      ['run', '--', ...dartRun('graph.dart')],
      dir: dir,
      stdin: File(p.join(dir, 'input.json')).readAsStringSync(),
    );
    expect(result.code, 0, reason: result.err);
    final id = result.out.trim();
    expect(result.out, '$id\n');
    final session = await sessionIn(dir, id);

    final graph = session.session.graph;
    final nodes = graph['nodes']! as Map<String, Object?>;
    expect(graph['start'], 'collect');
    expect(nodes.keys, [
      'collect',
      'isEmpty',
      'inspect',
      'verdict',
      'fix',
      'publish',
      'notify',
      'discard',
    ]);
    for (final node in nodes.values.cast<Map<String, Object?>>()) {
      expect(node['command'] ?? node['decide'], matches(r'^graph\.dart:\d+$'));
    }
    expect((nodes['verdict']! as Map<String, Object?>)['then'], {
      'accepted': ['publish', 'notify'],
      'returned': 'fix',
    });

    final [root, ...children] = await session.runs();
    expect(root.parentId, isNull);
    expect(await journal(session, root.id), [
      'run-started collect',
      for (final node in [
        'collect',
        'isEmpty',
        'inspect',
        'verdict',
        'fix',
        'inspect',
        'verdict',
      ]) ...['step-started $node', 'step-finished 0'],
      'run-split',
    ]);
    final steps = await session.steps(root.id);
    expect(await session.documentValue(steps.first.inputId!), {
      'branch': 'parseConfig',
    });
    const before = {'id': 'parseConfig', 'path': 'lib/parseConfig.dart'};
    const after = {'id': 'parseConfig', 'path': 'lib/parse_config.dart'};
    const accepted = {'change': after, 'findings': <String>[]};
    expect(
      [for (final step in steps) await session.documentValue(step.outputId!)],
      [
        before,
        false,
        {
          'change': before,
          'findings': ['lib/parseConfig.dart: file names are lower_snake_case'],
        },
        'returned',
        after,
        accepted,
        'accepted',
      ],
    );

    expect(children, hasLength(2));
    final logs = <String, String>{};
    for (final child in children) {
      expect(child.parentId, root.id);
      final [step] = await session.steps(child.id);
      final node = (await journal(session, child.id)).first.split(' ').last;
      expect(await journal(session, child.id), [
        'run-started $node',
        'step-started $node',
        'step-finished 0',
        'run-finished',
      ]);
      expect(await session.documentValue(step.inputId!), accepted);
      logs[node] = logOf(session, step);
    }
    expect(logs, {
      'publish': 'published lib/parse_config.dart\n',
      'notify': 'parseConfig: accepted\n',
    });
  });
}
