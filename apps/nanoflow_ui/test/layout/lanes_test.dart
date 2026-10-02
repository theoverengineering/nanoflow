import 'package:nanoflow_ui/layout/layout.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('a ladder down turns further right the higher it starts; a ladder up '
      'the lower it starts', () {
    final layout = layoutGraph(loadGraph('fork6'));
    // triage's exits: bug, feature go up; question, else, security,
    // duplicate go down.
    double turn(int exit) => verticals(edgeOf(layout, 'triage', exit)).first.$1;
    double start(int exit) => edgeOf(layout, 'triage', exit).points.first.y;
    final up = [0, 1]..sort((a, b) => start(a).compareTo(start(b)));
    expect(turn(up[0]), lessThan(turn(up[1])));
    final down = [3, 4, 5, 7]..sort((a, b) => start(a).compareTo(start(b)));
    for (var i = 1; i < down.length; i++) {
      expect(turn(down[i - 1]), greaterThan(turn(down[i])));
    }
  });

  test('turns in a gap take their own lanes a lane gap apart, even at '
      'heights far apart', () {
    // The review mockup: is-empty's true arrow turns up and the back arrow
    // from fix turns up into inspect in the same gap, far below it.
    final layout = layoutGraph(loadGraph('review'));
    final up = verticals(edgeOf(layout, 'is-empty', 0)).single;
    final back = verticals(edgeOf(layout, 'fix', 0)).last;
    expect(
      (up.$1 - back.$1).abs(),
      greaterThanOrEqualTo(layout.options.laneGap),
    );
  });

  test('a piece leaving a gap and one entering it at nearly the same height '
      'do not run along each other', () {
    // A random graph whose lanes ran two such pieces 7 px apart before
    // lanes kept them in order.
    final layout = layoutGraph(loadGraph('tangle'));
    expect(
      checkLayout(layout).where((problem) => problem.contains('parallel')),
      isEmpty,
    );
  });

  test('a change of height goes at 45° where that fits in the gap the lanes '
      'make', () {
    // As in the review mockup: one arrow turns far up on a lane, which makes
    // the gap wide enough for a small change of height to slant.
    final layout = layoutGraph(
      graphOf({
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
    final layout = layoutGraph(
      graphOf({
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
    final layout = layoutGraph(loadGraph('review'));
    final up = edgeOf(layout, 'is-empty', 0);
    expect(verticals(up), hasLength(1));
    expect(up.points.length, 4);
  });

  test('a long arrow runs straight through its corridor', () {
    final layout = layoutGraph(loadGraph('task'));
    // admit's human and review arrows go over the top, as in the mockup:
    // one height from their first turn to their last.
    for (final exit in [1, 2]) {
      final edge = edgeOf(layout, 'admit', exit);
      expect(edge.points, hasLength(6));
      expect(edge.points[2].y, edge.points[3].y);
      expect(edge.points[2].y, lessThan(layout.nodes['coder']!.tile.top));
    }
  });

  test('back arrows run under every node, a wider one lower', () {
    final layout = layoutGraph(loadGraph('task'));
    final lowest = layout.nodes.values
        .map((n) => n.commandRect.bottom)
        .reduce((a, b) => a > b ? a : b);
    final lanes = <String, double>{};
    for (final edge in layout.edges.where((e) => e.kind == EdgeKind.back)) {
      final lane = edge.points[2].y;
      expect(edge.points[3].y, lane);
      expect(lane, greaterThan(lowest));
      lanes['${edge.from}->${edge.to}#${edge.exitIndex}'] = lane;
    }
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
}
