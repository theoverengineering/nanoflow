import 'package:nanoflow_ui/layout/layout.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  /// The y of each exit of [node] by its key, `then` for a worker's.
  Map<String, double> exitYs(GraphLayout layout, String node) => {
    for (final exit in layout.exits)
      if (exit.node == node) exit.label ?? 'then': exit.anchor.y,
  };

  test('forward exits form a ladder: ordered by where their targets are, not '
      'by declaration', () {
    final layout = layoutGraph(loadGraph('task'));
    // admit declares fresh, review, human; human goes highest.
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
    final layout = layoutGraph(loadGraph('task'));
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

  test(
    'back exits come after forward ones, stubs last, else the very last',
    () {
      final layout = layoutGraph(loadGraph('task'));
      final ys = exitYs(layout, 'review-verdict');
      expect([...ys.keys]..sort((a, b) => ys[a]!.compareTo(ys[b]!)), [
        'pass',
        'fail',
        'again',
        'else',
      ]);
      final empty = layoutGraph(loadGraph('empty'));
      final route = exitYs(empty, 'route');
      expect([...route.keys]..sort((a, b) => route[a]!.compareTo(route[b]!)), [
        'store',
        'drop',
        'ignore',
        'else',
      ]);
    },
  );

  test('a stub is as long as its key with room for a counter, and arrows of '
      'its node turn only past it', () {
    final layout = layoutGraph(loadGraph('task'));
    final stub = exitOf(layout, 'coder-status', 3);
    expect(stub.shape, ExitShape.stub);
    final o = layout.options;
    final counter = o.measure('99×', LabelKind.counter) + 2 * o.chipPadding;
    expect(stub.stubEnd! - stub.counterAt.x, greaterThanOrEqualTo(counter));
    for (final exit in [1, 2]) {
      final down = verticals(edgeOf(layout, 'coder-status', exit)).first;
      expect(down.$1, greaterThan(stub.stubEnd!));
    }
  });

  test('a list target is one capsule: arrows a capsule gap apart in list '
      'order, one key', () {
    final layout = layoutGraph(loadGraph('capsules'));
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
    final review = layoutGraph(loadGraph('review'));
    expect(review.nodes['collect']!.tile.height, 80);
    final many = layoutGraph(loadGraph('many-sources'));
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
}
