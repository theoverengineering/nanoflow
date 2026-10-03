import 'package:nanoflow_ui/layout/layout.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  /// The y of each exit of [node] by its label, `then` without one.
  Map<String, double> exitYs(GraphLayout layout, String node) => {
    for (final exit in layout.exits)
      if (exit.node == node) exit.label ?? 'then': exit.anchor.y,
  };

  /// The labels of the exits of [node], top to bottom.
  List<String> exitsDown(GraphLayout layout, String node) {
    final ys = exitYs(layout, node);
    return [...ys.keys]..sort((a, b) => ys[a]!.compareTo(ys[b]!));
  }

  test('forward exits form a ladder: ordered by where their targets are, not '
      'by the body\'s order', () {
    final layout = layoutOf('task');
    // admit's edges go fresh, review, human; human goes highest.
    final ys = exitYs(layout, 'admit');
    expect(ys['human']!, lessThan(ys['review']!));
    expect(ys['review']!, lessThan(ys['fresh']!));
    // Forward inputs form the matching ladder: from the higher exit, higher.
    final reviewer = layout.nodes['reviewer']!.bar!.inputs;
    expect(edgeOf(layout, 'admit', 1).points.last.y, reviewer[0]);
    expect(edgeOf(layout, 'checks-result', 0).points.last.y, reviewer[1]);
  });

  test('back exits nest: the higher exit runs the lower lane and enters the '
      'higher input', () {
    final layout = layoutOf('task');
    final goOn = edgeOf(layout, 'coder-status', 1);
    final post = edgeOf(layout, 'coder-status', 2);
    double lane(EdgePath edge) =>
        edge.points.map((p) => p.y).reduce((a, b) => a > b ? a : b);
    expect(goOn.points.first.y, lessThan(post.points.first.y));
    expect(lane(goOn), greaterThan(lane(post)));
    expect(goOn.points.last.y, lessThan(post.points.last.y));
    // All five back arrows into coder: the lower the lane, the higher the
    // input.
    final into = [
      for (final e in layout.edges)
        if (e.to == 'coder' && e.kind == EdgeKind.back) e,
    ]..sort((a, b) => lane(b).compareTo(lane(a)));
    final inputs = [for (final e in into) e.points.last.y];
    expect(inputs, [...inputs]..sort());
  });

  test('back exits come after forward ones', () {
    final layout = layoutOf('task');
    expect(exitsDown(layout, 'review-verdict'), [
      'pass',
      'else',
      'fail',
      'again',
    ]);
    expect(exitsDown(layout, 'coder-status'), [
      'else',
      'done',
      'go-on',
      'post',
    ]);
  });

  test('a counter reads its count up to 999, then 1k+', () {
    expect(counterText(1), '1×');
    expect(counterText(999), '999×');
    expect(counterText(1000), '1k+×');
  });

  test('edges with one label are one capsule: arrows a capsule gap apart in '
      'the body\'s order, one label', () {
    final layout = layoutOf('capsules');
    final go = exitOf(layout, 'release', 0);
    expect(go.shape, ExitShape.capsule);
    expect(go.label, 'go');
    final starts = [
      for (var i = 0; i < 4; i++) edgeOf(layout, 'release', 0, i).points.first,
    ];
    for (var i = 1; i < 4; i++) {
      expect(starts[i].y - starts[i - 1].y, layout.options.capsuleGap);
      expect(starts[i].x, go.anchor.x);
    }
    expect(go.handle.top, lessThan(starts.first.y));
    expect(go.handle.bottom, greaterThan(starts.last.y));
    expect(go.labelRect!.bottom, lessThan(starts.first.y));
  });

  test('a tile grows for its exits and for its inputs, a port gap apart on '
      'the straight part of its side', () {
    final review = layoutOf('review');
    expect(review.nodes['1']!.tile.height, 80);
    final many = layoutOf('many-sources');
    final collect = many.nodes['collect']!;
    final bar = collect.bar!;
    expect(bar.inputs, hasLength(6));
    for (var i = 1; i < bar.inputs.length; i++) {
      expect(bar.inputs[i] - bar.inputs[i - 1], many.options.portGap);
    }
    expect(
      collect.tile.height,
      greaterThanOrEqualTo(bar.rect.height + 2 * many.options.tileRadius),
    );
    expect(collect.tile.height, greaterThan(80));
    final split = many.nodes['split']!;
    expect(split.tile.height, (6 + 1) * many.options.exitGap);
  });

  test('a marker is as wide as a tile and lower, and grows as a tile does', () {
    final layout = layoutOf('review');
    final o = layout.options;
    final start = layout.nodes[startMarker]!;
    expect(start.tile.width, o.tile);
    expect(start.tile.height, o.marker);
    final many = layoutBody(
      bodyOf({
        'start': ['a', 'b', 'c', 'd'],
        'nodes': {
          'a': {'command': 'a', 'then': <String>[]},
          'b': {'command': 'b', 'then': <String>[]},
          'c': {'command': 'c', 'then': <String>[]},
          'd': {'command': 'd', 'then': <String>[]},
        },
      }),
    );
    // One capsule of four arrows: an exit and a half for each over one.
    expect(many.nodes[startMarker]!.tile.height, (2.5 + 1) * o.exitGap);
  });
}
