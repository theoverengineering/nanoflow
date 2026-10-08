import 'dart:convert';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/layout/lanes.dart' show clearance;
import 'package:nanoflow_ui/layout/layout.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('a ladder down turns further right the higher it starts; a ladder up '
      'the lower it starts', () {
    final layout = layoutOf('fork6');
    // triage's arrows that turn in the first gap: (start, turn x, going down).
    final turns = [
      for (final edge in layout.edges)
        if (edge.from == 'triage' && verticals(edge).isNotEmpty)
          (
            edge.points.first.y,
            verticals(edge).first.$1,
            edge.points[2].y > edge.points[1].y,
          ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final up = [
      for (final t in turns)
        if (!t.$3) t,
    ];
    final down = [
      for (final t in turns)
        if (t.$3) t,
    ];
    expect(up.length, greaterThanOrEqualTo(2));
    expect(down.length, greaterThanOrEqualTo(2));
    for (var i = 1; i < up.length; i++) {
      expect(up[i - 1].$2, lessThan(up[i].$2));
    }
    for (var i = 1; i < down.length; i++) {
      expect(down[i - 1].$2, greaterThan(down[i].$2));
    }
  });

  test('turns in a gap take their own lanes a lane gap apart, even at '
      'heights far apart', () {
    // The review example: change.path.isEmpty's true arrow turns up and the
    // back arrow from fix turns up into inspect in the same gap, far below
    // it.
    final layout = layoutOf('review');
    final up = verticals(edgeOf(layout, '2', 0)).single;
    final back = verticals(edgeOf(layout, '8', 0)).last;
    expect(
      (up.$1 - back.$1).abs(),
      greaterThanOrEqualTo(layout.options.laneGap),
    );
  });

  test('a piece leaving a gap and one entering it at nearly the same height '
      'do not run along each other', () {
    // A random graph whose lanes ran two such pieces 7 px apart before
    // lanes kept them in order.
    final layout = layoutOf('tangle');
    expect(
      checkLayout(layout).where((problem) => problem.contains('parallel')),
      isEmpty,
    );
  });

  test('a change of height goes at 45° where that fits in the gap the lanes '
      'make', () {
    // As in the review mockup: one arrow turns far up on a lane, which makes
    // the gap wide enough for a small change of height to slant.
    final layout = layoutBody(
      bodyOf({
        'start': 's',
        'nodes': {
          's': {
            'decide': 's',
            'then': {'up': 'x', 'a': 'n', 'b': 'n'},
          },
          'x': {'command': 'x'},
          'n': {'command': 'n', 'then': 'm'},
          'm': {'command': 'm'},
        },
      }),
    );
    expect(verticals(edgeOf(layout, 's', 0)), hasLength(1));
    expect(edgeOf(layout, 's', 1).points, hasLength(2));
    final slanted = edgeOf(layout, 's', 2);
    expect(slanted.points, hasLength(4));
    final d = slanted.points[2] - slanted.points[1];
    expect(d.x.abs(), closeTo(d.y.abs(), 1e-9));
    expect(d.x, greaterThan(0));
    // Nothing turns where it slants at heights near its own.
    final top = slanted.points[2].y < slanted.points[1].y
        ? slanted.points[2].y
        : slanted.points[1].y;
    final bottom = top + d.y.abs();
    final gap = layout.options.laneGap;
    for (final other in layout.edges) {
      if (identical(other, slanted)) continue;
      for (final (x, from, to) in verticals(other)) {
        final inStretch =
            x >= slanted.points[1].x - gap && x <= slanted.points[2].x + gap;
        final nearHeight = from < bottom + gap && top < to + gap;
        expect(inStretch && nearHeight, isFalse, reason: 'turns at $x');
      }
    }
  });

  test('a change of height alone in its gap turns on a lane unless it is '
      'smaller than the lane\'s corners', () {
    final layout = layoutBody(
      bodyOf({
        'start': 's',
        'nodes': {
          's': {
            'decide': 's',
            'then': {'a': 'n', 'b': 'n'},
          },
          'n': {'command': 'n'},
        },
      }),
    );
    expect(edgeOf(layout, 's', 0).points, hasLength(2));
    final jog = edgeOf(layout, 's', 1);
    expect(verticals(jog), hasLength(1));
  });

  test('a big change of height turns on a vertical lane', () {
    final layout = layoutOf('review');
    final up = edgeOf(layout, '2', 0);
    expect(verticals(up), hasLength(1));
    expect(up.points.length, 4);
  });

  test('a long arrow runs straight through its corridor', () {
    final layout = layoutOf('task');
    // admit's human and review arrows go over the top, as in the mockup:
    // one height from their first turn to their last.
    for (final exit in [1, 2]) {
      final edge = edgeOf(layout, 'admit', exit);
      expect(edge.points, hasLength(6));
      expect(edge.points[2].y, edge.points[3].y);
      expect(edge.points[2].y, lessThan(layout.nodes['coder']!.tile.top));
    }
  });

  test('back arrows run under every node between their ends, a wider one '
      'lower', () {
    final layout = layoutOf('task');
    final lanes = <String, double>{};
    for (final edge in layout.edges.where((e) => e.kind == EdgeKind.back)) {
      final lane = edge.points[2].y;
      expect(edge.points[3].y, lane);
      final left = layout.nodes[edge.to]!.tile.left;
      final right = layout.nodes[edge.from]!.tile.right;
      for (final node in layout.nodes.values) {
        if (node.tile.left < left || node.tile.right > right) continue;
        expect(lane, greaterThan(node.placeRect.bottom));
      }
      lanes['${edge.from}->${edge.to}#${edge.exitIndex}'] = lane;
    }
    // review's way back runs under review alone: above coder's innermost,
    // which shares no gap with it but passes the taller coder-status.
    expect(
      lanes['review-verdict->reviewer#2']!,
      lessThan(lanes['coder-status->coder#2']!),
    );
    expect(
      lanes['human-answer->coder#1']!,
      greaterThan(lanes['review-verdict->coder#1']!),
    );
    expect(
      lanes['review-verdict->coder#1']!,
      greaterThan(lanes['checks-result->coder#1']!),
    );
    expect(
      lanes['checks-result->coder#1']!,
      greaterThan(lanes['coder-status->coder#1']!),
    );
  });

  test('a back arrow runs under what lies between its ends, not under the '
      'whole level', () {
    // The user's agreeCut(), writeAndReviewCut() drawn in place: the way
    // back of the loop after the frame ran under the frame, far below the
    // loop.
    GraphBody body(String json) =>
        GraphBody.fromJson(jsonDecode(json) as Map<String, Object?>);
    final layout = layoutBody(
      body(_agreeCut),
      expanded: {'1': ExpandedNode(body(_writeAndReviewCut))},
    );
    final frame = layout.nodes['1']!.tile;
    final ask = layout.nodes['6']!;
    final loop = edgeOf(layout, '6', 0);
    final round = edgeOf(layout, '3', 1);
    expect(loop.points[2].y, loop.points[3].y);
    expect(loop.points[2].y, greaterThan(ask.placeRect.bottom));
    expect(loop.points[2].y, lessThan(frame.bottom));
    // The way back to the frame passes under it.
    expect(round.points[2].y, greaterThan(frame.bottom));
    expect(checkLayout(layout), isEmpty);
  });

  group('a layer as wide as a frame in it', () {
    // g() drawn in place: four steps in a row, a frame much wider than a
    // tile.
    final wide = {
      'f': ExpandedNode(
        GraphBody(
          nodes: [
            for (var i = 0; i < 4; i++)
              EffectNode(id: 'g$i', place: 'lib/a.dart:${i + 20}', name: 'g$i'),
          ],
          edges: [
            for (var i = 0; i <= 4; i++)
              GraphEdge(
                from: i == 0 ? null : 'g${i - 1}',
                to: i == 4 ? null : 'g$i',
                label: null,
              ),
          ],
        ),
      ),
    };
    const check = ConditionNode(id: 's', place: 'lib/a.dart:2', label: 'check');
    const call = CallNode(
      id: 'f',
      place: 'lib/a.dart:3',
      functions: ['lib/a.dart#g'],
    );
    const done = EffectNode(id: 't', place: 'lib/a.dart:5', name: 'done');

    test('the way back of a tile under the frame goes down next to the '
        'tile, though a long arrow turns up at the layer\'s side before it '
        'in the lanes\' order', () {
      final layout = layoutBody(
        const GraphBody(
          nodes: [
            check,
            call,
            EffectNode(id: 'n', place: 'lib/a.dart:4', name: 'retry'),
            done,
          ],
          edges: [
            GraphEdge(from: null, to: 's', label: null),
            GraphEdge(from: 's', to: 'f', label: 'ok'),
            GraphEdge(from: 's', to: 'n', label: 'again'),
            GraphEdge(from: 's', to: 't', label: 'skip'),
            GraphEdge(from: 'f', to: 't', label: null),
            GraphEdge(from: 'n', to: 's', label: null),
            GraphEdge(from: 't', to: null, label: null),
          ],
        ),
        expanded: wide,
      );
      expect(checkLayout(layout), isEmpty);
      expect(countCrossings(layout), 0);
      final frame = layout.nodes['f']!.tile;
      expect(layout.nodes['n']!.tile.top, greaterThan(frame.bottom));
      final (back, _, _) = verticals(edgeOf(layout, 'n', 0)).first;
      expect(back, closeTo(turnDownBeside(layout, 'n', 0), 1e-9));
      // The long arrow from check to done comes up past the frame: right
      // of it, a clearance off its side.
      final (up, top, _) = verticals(edgeOf(layout, 's', 2)).last;
      expect(top, lessThan(frame.bottom));
      expect(up - frame.right, greaterThanOrEqualTo(clearance));
    });

    test('a tile\'s way on into a node at the frame\'s height turns right of '
        'the frame, a clearance off its side, as it passes the frame\'s '
        'heights; its way back next to the tile', () {
      final layout = layoutBody(
        const GraphBody(
          nodes: [
            check,
            call,
            ConditionNode(id: 'n', place: 'lib/a.dart:4', label: 'give up?'),
            done,
          ],
          edges: [
            GraphEdge(from: null, to: 's', label: null),
            GraphEdge(from: 's', to: 'n', label: 'again'),
            GraphEdge(from: 's', to: 'f', label: 'ok'),
            GraphEdge(from: 'n', to: 's', label: 'false'),
            GraphEdge(from: 'n', to: 't', label: 'true'),
            GraphEdge(from: 'f', to: 't', label: null),
            GraphEdge(from: 't', to: null, label: null),
          ],
        ),
        expanded: wide,
      );
      expect(checkLayout(layout), isEmpty);
      expect(countCrossings(layout), 0);
      final frame = layout.nodes['f']!.tile;
      expect(layout.nodes['n']!.tile.top, greaterThan(frame.bottom));
      expect(layout.nodes['t']!.tile.top, lessThan(frame.bottom));
      final (on, top, _) = verticals(edgeOf(layout, 'n', 1)).single;
      expect(top, lessThan(frame.bottom));
      expect(on - frame.right, greaterThanOrEqualTo(clearance));
      final (back, _, _) = verticals(edgeOf(layout, 'n', 0)).first;
      expect(back, closeTo(turnDownBeside(layout, 'n', 0), 1e-9));
    });
  });
}

/// agreeCut() of the user's lib/chain.dart, as describe wrote it.
const _agreeCut = r'''
{"nodes":[{"id":"1","kind":"call","functions":["lib/chain.dart#writeAndReviewCut"],"place":"lib/chain.dart:381"},{"id":"2","kind":"effect","name":"you review the cut","place":"lib/chain.dart:388"},{"id":"3","kind":"fork","label":"switch (decision.choice)","place":"lib/chain.dart:395"},{"id":"4","kind":"effect","name":"lay out the tasks","place":"lib/chain.dart:398"},{"id":"5","kind":"fork","label":"refused == null","place":"lib/chain.dart:402"},{"id":"6","kind":"effect","name":"ask you: refused","place":"lib/chain.dart:403"}],"edges":[{"from":null,"to":"1","label":null},{"from":"1","to":"2","label":null},{"from":"2","to":"3","label":null},{"from":"3","to":"4","label":"Choice.accept"},{"from":"3","to":"1","label":"Choice.changes"},{"from":"4","to":"5","label":null},{"from":"5","to":null,"label":"true"},{"from":"5","to":"6","label":"false"},{"from":"6","to":"4","label":null}]}''';

/// writeAndReviewCut() of the user's lib/chain.dart, as describe wrote it.
const _writeAndReviewCut = r'''
{"nodes":[{"id":"1","kind":"fork","label":"cutter != null","place":"lib/chain.dart:432"},{"id":"2","kind":"call","functions":["lib/chain.dart#writeCut"],"place":"lib/chain.dart:433"},{"id":"3","kind":"call","functions":["lib/chain.dart#reviewCut"],"place":"lib/chain.dart:437"},{"id":"4","kind":"fork","label":"verdict.passed","place":"lib/chain.dart:445"},{"id":"5","kind":"fork","label":"freshPass","place":"lib/chain.dart:446"},{"id":"6","kind":"fork","label":"failures >= maxRounds","place":"lib/chain.dart:459"},{"id":"7","kind":"effect","name":"ask you: dispute","place":"lib/chain.dart:464"}],"edges":[{"from":null,"to":"1","label":null},{"from":"1","to":"2","label":"true"},{"from":"1","to":"3","label":"false"},{"from":"2","to":"3","label":null},{"from":"3","to":"4","label":null},{"from":"4","to":"5","label":"true"},{"from":"4","to":"6","label":"false"},{"from":"5","to":null,"label":"true"},{"from":"5","to":"1","label":"false"},{"from":"6","to":"7","label":"true"},{"from":"6","to":"1","label":"false"},{"from":"7","to":"1","label":null}]}''';
