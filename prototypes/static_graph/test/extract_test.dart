import 'package:static_graph/extract.dart';
import 'package:test/test.dart';

void main() {
  test('reads the README review graph from an ordinary function', () async {
    final (:graph, :warnings) = await extractGraph(
      'example/review.dart',
      'review',
    );
    expect(warnings, isEmpty);
    expect(graph, {
      'start': 'collect',
      'nodes': {
        'collect': {'command': 'review.dart:22', 'then': 'change.path.isEmpty'},
        'change.path.isEmpty': {
          'decide': 'review.dart:23',
          'then': 'discard',
          'else': 'inspect',
        },
        'discard': {'command': 'review.dart:24'},
        'inspect': {
          'command': 'review.dart:28',
          'then': 'report.findings.isEmpty',
        },
        'report.findings.isEmpty': {
          'decide': 'review.dart:29',
          'then': ['publish', 'notify'],
          'else': 'fix',
        },
        'publish': {'command': 'review.dart:31'},
        'notify': {'command': 'review.dart:32'},
        'fix': {'command': 'review.dart:36', 'then': 'inspect'},
      },
    });
  });

  for (final function in ['inPlace', 'viaMap']) {
    test('draws copies side by side written in place: $function', () async {
      final (:graph, :warnings) = await extractGraph(
        'example/inline.dart',
        function,
      );
      expect(warnings, isEmpty);
      final nodes = graph['nodes']! as Map<String, Object?>;
      const copies = '∥ for pkg in packages';
      expect(graph['start'], copies);
      expect(nodes[copies], containsPair('then', 'upload'));
      expect(nodes[copies], containsPair('else', 'announce'));
      expect((nodes['upload']! as Map)['then'], 'verify');
      expect((nodes['verify']! as Map)['then'], 'tag');
      // The copies are joined: no way back, the run goes on to announce.
      expect((nodes['tag']! as Map)['then'], 'announce');
    });
  }

  test('draws an ordinary for written in place as a loop', () async {
    final (:graph, :warnings) = await extractGraph(
      'example/inline.dart',
      'sequential',
    );
    expect(warnings, isEmpty);
    final nodes = graph['nodes']! as Map<String, Object?>;
    const loop = 'for pkg in packages';
    expect(nodes[loop], containsPair('then', 'upload'));
    expect(nodes[loop], containsPair('else', 'announce'));
    expect((nodes['tag']! as Map)['then'], loop);
  });

  test('follows a loop over data, a switch and a called function', () async {
    final (:graph, :warnings) = await extractGraph(
      'example/release.dart',
      'release',
    );
    expect(warnings, isEmpty);
    final nodes = graph['nodes']! as Map<String, Object?>;
    const loop = 'for pkg in plan.packages';
    expect(nodes[loop], {
      'decide': 'release.dart:21',
      'then': 'build',
      'else': 'switch (plan.channel)',
    });
    // Every way out of the loop body goes back to the loop.
    expect((nodes['pkg.isPublic']! as Map)['else'], loop);
    expect((nodes['!ok']! as Map)['else'], loop);
    expect((nodes['rollback']! as Map)['then'], loop);
    // Steps of publish(), called from the loop, are part of the graph.
    expect((nodes['upload']! as Map)['then'], 'verify');
    expect((nodes['switch (plan.channel)']! as Map)['then'], {
      'Channel.stable': 'announce',
      'Channel.beta': 'notify-testers',
      'Channel.dev': 'notify-testers',
    });
  });
}
