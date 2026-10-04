import 'package:nanoflow_ui/layout/layout.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late GraphLayout good;
  setUpAll(() => good = layoutOf('review'));

  /// [good] with the points of the arrow from [from]'s exit [exit] replaced.
  GraphLayout withPoints(String from, int exit, List<Point> points) =>
      GraphLayout(
        nodes: good.nodes,
        exits: good.exits,
        edges: [
          for (final e in good.edges)
            if (e.from == from && e.exitIndex == exit)
              EdgePath(
                from: e.from,
                exitIndex: e.exitIndex,
                listIndex: e.listIndex,
                edgeIndex: e.edgeIndex,
                to: e.to,
                kind: e.kind,
                points: points,
                tip: points.last + Point(good.options.arrowLength, 0),
                pieces: roundCorners(points, good.options.cornerRadius),
              )
            else
              e,
        ],
        bounds: good.bounds,
        options: good.options,
      );

  test('a good layout breaks nothing', () {
    expect(checkLayout(good), isEmpty);
  });

  test('an arrow through a tile', () {
    // The false arrow of change.path.isEmpty, straight through discard's
    // column instead.
    final edge = edgeOf(good, '2', 1);
    final discard = good.nodes['3']!.tile;
    final y = discard.center.y;
    final points = [
      edge.points.first,
      Point(edge.points.first.x + 80, edge.points.first.y),
      Point(edge.points.first.x + 80, y),
      Point(discard.right + 30, y),
      Point(discard.right + 30, edge.points.last.y),
      edge.points.last,
    ];
    expect(
      checkLayout(withPoints('2', 1, points)),
      contains(contains('passes through 3')),
    );
  });

  test('pieces that are not horizontal, vertical or at 45°', () {
    final edge = edgeOf(good, '2', 0);
    final points = [
      edge.points.first,
      Point(edge.points.first.x + 80, edge.points.first.y),
      Point(edge.points.last.x - 30, edge.points.last.y),
      edge.points.last,
    ];
    expect(
      checkLayout(withPoints('2', 0, points)),
      contains(contains('not horizontal, vertical or at 45°')),
    );
  });

  test('parallel pieces closer than a lane gap', () {
    // Lay change.path.isEmpty's true arrow along its false arrow, 5 px
    // over it.
    final other = edgeOf(good, '2', 1);
    final edge = edgeOf(good, '2', 0);
    final y = other.points.first.y - 5;
    final points = [
      edge.points.first,
      Point(edge.points.first.x + 70, edge.points.first.y),
      Point(edge.points.first.x + 70, y),
      Point(other.points.last.x - 40, y),
      Point(other.points.last.x - 40, edge.points.last.y),
      edge.points.last,
    ];
    expect(
      checkLayout(withPoints('2', 0, points)),
      contains(contains('5.0 apart')),
    );
  });

  test('a turn before the end of the label, or too close to the input', () {
    final edge = edgeOf(good, '2', 0);
    final first = edge.points.first;
    final last = edge.points.last;
    final early = [
      first,
      Point(first.x + 20, first.y),
      Point(first.x + 20, last.y),
      last,
    ];
    expect(
      checkLayout(withPoints('2', 0, early)),
      contains(contains('shorter than its label')),
    );
    final late = [
      first,
      Point(last.x - 15, first.y),
      Point(last.x - 15, last.y),
      last,
    ];
    expect(
      checkLayout(withPoints('2', 0, late)),
      contains(contains('straight piece at the input')),
    );
  });

  test('an arrowhead that does not point at the bar with a gap', () {
    final edge = edgeOf(good, '1', 0);
    final points = [edge.points.first, edge.points.last + const Point(6, 0)];
    expect(
      checkLayout(withPoints('1', 0, points)),
      contains(contains('is not an arrow gap before the bar')),
    );
  });

  test('a loop that crosses another arrow', () {
    final loops = layoutOf('loops');
    final retry = edgeOf(loops, 'fetch-check', 0);
    final skip = edgeOf(loops, 'fetch-check', 2);
    // Move the retry loop's far side down through skip's vertical.
    final low = skip.points[2].y - 5;
    final points = [
      retry.points.first,
      Point(skip.points[1].x + 20, retry.points.first.y),
      Point(skip.points[1].x + 20, low),
      Point(retry.points[3].x, low),
      Point(retry.points[3].x, retry.points.last.y),
      retry.points.last,
    ];
    final broken = GraphLayout(
      nodes: loops.nodes,
      exits: loops.exits,
      edges: [
        for (final e in loops.edges)
          identical(e, retry)
              ? EdgePath(
                  from: e.from,
                  exitIndex: e.exitIndex,
                  listIndex: e.listIndex,
                  edgeIndex: e.edgeIndex,
                  to: e.to,
                  kind: e.kind,
                  points: points,
                  tip: e.tip,
                  pieces: e.pieces,
                )
              : e,
      ],
      bounds: loops.bounds,
      options: loops.options,
    );
    expect(checkLayout(broken), contains(contains('loop crosses')));
  });

  test('crossings count every pair of crossing pieces', () {
    expect(countCrossings(good), 0);
    final edge = edgeOf(good, '2', 0);
    final other = edgeOf(good, '2', 1);
    // Swap the true arrow's end below the false arrow: it crosses it on
    // the way down and on the way up, a third into the gap and a third
    // before its end.
    final below = other.points.first.y + 20;
    final third = (edge.points.last.x - edge.points.first.x) / 3;
    final down = edge.points.first.x + third;
    final up = edge.points.last.x - third;
    final points = [
      edge.points.first,
      Point(down, edge.points.first.y),
      Point(down, below),
      Point(up, below),
      Point(up, edge.points.last.y),
      edge.points.last,
    ];
    expect(countCrossings(withPoints('2', 0, points)), 2);
  });
}
