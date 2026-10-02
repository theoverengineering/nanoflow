import 'package:nanoflow_ui/layout/layout.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final names = graphNames();

  test('the test graphs include the two mockup graphs', () {
    expect(names, containsAll(['review', 'task']));
  });

  test('every test graph has a reference crossing count', () {
    expect(referenceCrossings().keys.toSet(), names.toSet());
  });

  for (final name in names) {
    group(name, () {
      late GraphLayout layout;
      setUpAll(() => layout = layoutGraph(loadGraph(name)));

      test('keeps every rule of step 9', () {
        expect(checkLayout(layout), isEmpty);
      });

      test('crosses no more than its reference layout', () {
        final reference = referenceCrossings()[name];
        expect(reference, isNotNull, reason: 'no reference for $name');
        expect(countCrossings(layout), lessThanOrEqualTo(reference!));
      });

      test('is the same every time', () {
        expect(describe(layoutGraph(loadGraph(name))), describe(layout));
      });

      test('starts at (0, 0) and holds everything it draws', () {
        final bounds = layout.bounds;
        expect((bounds.left, bounds.top), (0, 0));
        bool inside(Point p) =>
            p.x >= -1e-9 &&
            p.y >= -1e-9 &&
            p.x <= bounds.right + 1e-9 &&
            p.y <= bounds.bottom + 1e-9;
        for (final node in layout.nodes.values) {
          for (final rect in [node.tile, node.nameRect, node.commandRect]) {
            expect(inside(Point(rect.left, rect.top)), isTrue);
            expect(inside(Point(rect.right, rect.bottom)), isTrue);
          }
        }
        for (final edge in layout.edges) {
          expect(edge.points.every(inside), isTrue);
        }
      });

      test('has a box for every node and exit and a path for every arrow', () {
        final graph = loadGraph(name);
        expect(layout.nodes.keys, graph.nodes.keys);
        expect(
          layout.exits.length,
          graph.nodes.values.fold(0, (n, node) => n + node.exits.length),
        );
        expect(
          layout.edges.length,
          graph.nodes.values.fold(
            0,
            (n, node) =>
                n + node.exits.fold(0, (m, e) => m + e.target.names.length),
          ),
        );
      });
    });
  }
}
