import 'package:nanoflow_ui/layout/layout.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late GraphLayout layout;
  setUpAll(() => layout = layoutOf('loops'));

  /// The highest and lowest y of [edge].
  (double, double) heights(EdgePath edge) {
    final ys = edge.points.map((p) => p.y);
    return (
      ys.reduce((a, b) => a < b ? a : b),
      ys.reduce((a, b) => a > b ? a : b),
    );
  }

  test('a loop goes over its tile, from its top exit to its top input', () {
    final retry = edgeOf(layout, 'fetch-check', 0);
    expect(retry.kind, EdgeKind.loop);
    final node = layout.nodes['fetch-check']!;
    expect(heights(retry).$1, lessThan(node.tile.top));
    expect(heights(retry).$2, lessThan(node.tile.bottom));
    final exitYs = [
      for (final exit in layout.exits)
        if (exit.node == 'fetch-check') exit.anchor.y,
    ]..sort();
    expect(retry.points.first.y, exitYs.first);
    expect(retry.points.last.y, node.bar!.inputs.first);
  });

  test('loops on one side nest: the first declared is innermost, and none '
      'crosses another', () {
    final retry = edgeOf(layout, 'fetch-check', 0);
    final wait = edgeOf(layout, 'fetch-check', 1);
    expect(heights(wait).$1, lessThan(heights(retry).$1));
    expect(retry.points.first.y, lessThan(wait.points.first.y));
    expect(retry.points.last.y, lessThan(wait.points.last.y));
    double right(EdgePath e) =>
        e.points.map((p) => p.x).reduce((a, b) => a > b ? a : b);
    double left(EdgePath e) =>
        e.points.skip(1).map((p) => p.x).reduce((a, b) => a < b ? a : b);
    expect(right(wait), greaterThan(right(retry)));
    expect(left(wait), lessThan(left(retry)));
  });

  test('a loop clears the badges over its tile', () {
    final node = layout.nodes['fetch-check']!;
    expect(
      heights(edgeOf(layout, 'fetch-check', 0)).$1,
      lessThan(node.marks.top),
    );
  });

  test('a loop goes under its tile, round its name and place, when over '
      'it it would cross another arrow', () {
    // build's capsule sends its first arrow on and loops with its second:
    // over the tile the loop would cross the first.
    final loop = edgeOf(layout, 'build', 0, 1);
    expect(loop.kind, EdgeKind.loop);
    final node = layout.nodes['build']!;
    expect(heights(loop).$1, greaterThan(node.tile.top));
    expect(heights(loop).$2, greaterThan(node.placeRect.bottom));
    expect(loop.points.last.y, node.bar!.inputs.last);
    expect(checkLayout(layout), isEmpty);
  });
}
