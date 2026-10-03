import 'package:nanoflow_ui/layout/layout.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final names = graphNames();
  final reference = referenceCrossings();

  test('the test graphs include the review example and the task mockup', () {
    expect(names, containsAll(['review', 'task']));
  });

  final bodies = {
    for (final name in names)
      for (final MapEntry(key: id, value: body) in bodiesOf(
        loadGraphFile(name),
      ).entries)
        '$name/$id': (loadGraphFile(name), body),
  };

  test('every body of the test graphs has a reference crossing count', () {
    expect(reference.keys.toSet(), bodies.keys.toSet());
  });

  for (final MapEntry(key: name, value: (file, body)) in bodies.entries) {
    group(name, () {
      late GraphLayout layout;
      GraphLayout lay() => layoutBody(body, functions: file.functions);
      setUpAll(() => layout = lay());

      test('keeps every rule of step 9', () {
        expect(checkLayout(layout), isEmpty);
      });

      test('crosses no more than its reference layout', () {
        expect(reference[name], isNotNull, reason: 'no reference for $name');
        expect(countCrossings(layout), lessThanOrEqualTo(reference[name]!));
      });

      test('is the same every time', () {
        expect(describe(lay()), describe(layout));
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
          for (final rect in [node.tile, node.nameRect, node.placeRect]) {
            expect(inside(Point(rect.left, rect.top)), isTrue);
            expect(inside(Point(rect.right, rect.bottom)), isTrue);
          }
        }
        for (final edge in layout.edges) {
          expect(edge.points.every(inside), isTrue);
        }
      });

      test('has a box for every node and marker, an exit for every label '
          'out of a node and a path for every edge', () {
        final ends = body.edges.where((e) => e.to == null).length;
        expect(layout.nodes.keys, [
          if (body.edges.any((e) => e.from == null)) startMarker,
          for (final node in body.nodes) node.id,
          for (var n = 1; n <= ends; n++) endMarkerAt(n),
        ]);
        expect(
          layout.exits.length,
          {for (final edge in body.edges) (edge.from, edge.label)}.length,
        );
        expect(layout.edges.length, body.edges.length);
      });
    });
  }
}
