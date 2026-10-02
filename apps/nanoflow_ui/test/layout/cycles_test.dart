import 'package:nanoflow_ui/layout/cycles.dart';
import 'package:nanoflow_ui/layout/layout_graph.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The kind of every arrow, as `from->to: kind`.
Map<String, EdgeKind> kinds(LayoutGraph graph) => {
  for (final e in graph.edges) '${e.from.name}->${e.to.name}': e.kind,
};

void main() {
  test('an arrow into a node on the walk\'s stack is back, into its own node '
      'a loop, any other forward', () {
    final graph = LayoutGraph.of(
      graphOf({
        'start': 'a',
        'nodes': {
          'a': {'command': 'a', 'then': 'b'},
          'b': {
            'decide': 'b',
            'then': {'again': 'b', 'back': 'a', 'on': 'c'},
          },
          'c': {'command': 'c'},
        },
      }),
    );
    findBackEdges(graph);
    expect(kinds(graph), {
      'a->b': EdgeKind.forward,
      'b->b': EdgeKind.loop,
      'b->a': EdgeKind.back,
      'b->c': EdgeKind.forward,
    });
  });

  test('the walk takes exits in declaration order, so that order decides '
      'which arrow of a cycle is back', () {
    Map<String, EdgeKind> walk(Map<String, Object?> then) {
      final graph = LayoutGraph.of(
        graphOf({
          'start': 's',
          'nodes': {
            's': {'decide': 's', 'then': then},
            'x': {'command': 'x', 'then': 'y'},
            'y': {'command': 'y', 'then': 'x'},
          },
        }),
      );
      findBackEdges(graph);
      return kinds(graph);
    }

    expect(walk({'one': 'x', 'two': 'y'}), {
      's->x': EdgeKind.forward,
      's->y': EdgeKind.forward,
      'x->y': EdgeKind.forward,
      'y->x': EdgeKind.back,
    });
    expect(walk({'two': 'y', 'one': 'x'}), {
      's->y': EdgeKind.forward,
      's->x': EdgeKind.forward,
      'x->y': EdgeKind.back,
      'y->x': EdgeKind.forward,
    });
  });

  test('the walk goes from the start nodes in their order, then from nodes '
      'nothing reached, in declaration order', () {
    final graph = LayoutGraph.of(
      graphOf({
        'start': ['b', 'a'],
        'nodes': {
          'lost': {'command': 'lost', 'then': 'a'},
          'a': {'command': 'a', 'then': 'c'},
          'b': {'command': 'b', 'then': 'c'},
          'c': {'command': 'c'},
        },
      }),
    );
    final order = findBackEdges(graph).map((n) => n.name);
    expect(order, ['b', 'c', 'a', 'lost']);
  });

  test('in the task mockup graph the back arrows are the dashed ones', () {
    final graph = LayoutGraph.of(loadGraph('task'));
    findBackEdges(graph);
    final back = [
      for (final e in graph.edges)
        if (e.kind == EdgeKind.back) '${e.exit}->${e.to.name}',
    ];
    expect(back, [
      'coder-status.go-on->coder',
      'coder-status.post->coder',
      'checks-result.repair->coder',
      'review-verdict.fail->coder',
      'review-verdict.again->reviewer',
      'human-answer.changes->coder',
    ]);
  });
}
