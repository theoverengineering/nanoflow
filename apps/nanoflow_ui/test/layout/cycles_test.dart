import 'package:nanoflow_ui/layout/cycles.dart';
import 'package:nanoflow_ui/layout/layers.dart';
import 'package:nanoflow_ui/layout/layout_graph.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The kind of every arrow, as `from->to: kind`.
Map<String, EdgeKind> kinds(LayoutGraph graph) => {
  for (final e in graph.edges) '${e.from.id}->${e.to.id}': e.kind,
};

void main() {
  test('an arrow into a node on the walk\'s stack is back, into its own node '
      'a loop, any other forward', () {
    final graph = LayoutGraph.ofBody(
      bodyOf({
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
      '$startMarker->a': EdgeKind.forward,
      'a->b': EdgeKind.forward,
      'b->b': EdgeKind.loop,
      'b->a': EdgeKind.back,
      'b->c': EdgeKind.forward,
    });
  });

  test('the body\'s order decides which arrow of a cycle is back, whichever '
      'exit the walk takes first', () {
    Map<String, EdgeKind> walk(
      Map<String, Object?> then, {
      bool yFirst = false,
    }) {
      final x = {'command': 'x', 'then': 'y'};
      final y = {'command': 'y', 'then': 'x'};
      final graph = LayoutGraph.ofBody(
        bodyOf({
          'start': 's',
          'nodes': {
            's': {'decide': 's', 'then': then},
            if (yFirst) 'y': y,
            'x': x,
            if (!yFirst) 'y': y,
          },
        }),
      );
      findBackEdges(graph);
      return kinds(graph)..remove('$startMarker->s');
    }

    const xFirst = {
      's->x': EdgeKind.forward,
      's->y': EdgeKind.forward,
      'x->y': EdgeKind.forward,
      'y->x': EdgeKind.back,
    };
    expect(walk({'one': 'x', 'two': 'y'}), xFirst);
    // The walk takes y first, yet x stands first in the body.
    expect(walk({'two': 'y', 'one': 'x'}), {
      's->y': EdgeKind.forward,
      's->x': EdgeKind.forward,
      'x->y': EdgeKind.forward,
      'y->x': EdgeKind.back,
    });
    expect(walk({'one': 'x', 'two': 'y'}, yFirst: true), {
      's->x': EdgeKind.forward,
      's->y': EdgeKind.forward,
      'y->x': EdgeKind.forward,
      'x->y': EdgeKind.back,
    });
  });

  test('a fork whose true goes into a cycle after the node its false goes to '
      'leaves that node first, as `stage = X; continue` back to an earlier '
      'case does', () {
    // `if (written) review else write`, then `write → review`, and review
    // back to write: write stands first in the body.
    final graph = LayoutGraph.ofBody(
      bodyOf({
        'start': 'c',
        'nodes': {
          'c': {
            'decide': 'c',
            'then': {'true': 'review', 'false': 'write'},
          },
          'write': {'command': 'write', 'then': 'review'},
          'review': {'command': 'review', 'then': 'write'},
        },
      }),
    );
    findBackEdges(graph);
    expect(kinds(graph)..remove('$startMarker->c'), {
      'c->review': EdgeKind.forward,
      'c->write': EdgeKind.forward,
      'write->review': EdgeKind.forward,
      'review->write': EdgeKind.back,
    });
    assignLayers(graph);
    final layer = {for (final n in graph.nodes) n.id: n.layer};
    expect(layer['write']!, lessThan(layer['review']!));
  });

  test('at a fork of true and false the walk takes true first, whichever '
      'the body lists first', () {
    final graph = LayoutGraph.ofBody(
      bodyOf({
        'start': 'c',
        'nodes': {
          'c': {
            'decide': 'c',
            'then': {'false': 'x', 'true': 'y'},
          },
          'x': {'command': 'x', 'then': 'z'},
          'y': {'command': 'y', 'then': 'z'},
          'z': {'command': 'z'},
        },
      }),
    );
    final order = findBackEdges(graph).map((n) => n.id);
    expect(order, [startMarker, 'c', 'y', 'z', 'x']);
  });

  test('the walk goes from the start marker through its arrows in order, '
      'then from nodes nothing reached, in the body\'s order', () {
    final graph = LayoutGraph.ofBody(
      bodyOf({
        'start': ['b', 'a'],
        'nodes': {
          'lost': {'command': 'lost', 'then': 'a'},
          'a': {'command': 'a', 'then': 'c'},
          'b': {'command': 'b', 'then': 'c'},
          'c': {'command': 'c', 'then': <String>[]},
        },
      }),
    );
    final order = findBackEdges(graph).map((n) => n.id);
    expect(order, [startMarker, 'b', 'c', endMarker, 'a', 'lost']);
  });

  test('in the task mockup graph the back arrows are the dashed ones', () {
    final graph = LayoutGraph.ofBody(loadBody('task'));
    findBackEdges(graph);
    final back = [
      for (final e in graph.edges)
        if (e.kind == EdgeKind.back) '${e.exit}->${e.to.id}',
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
