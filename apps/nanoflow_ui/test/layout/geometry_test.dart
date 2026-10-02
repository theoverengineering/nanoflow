import 'package:nanoflow_ui/layout/geometry.dart';
import 'package:test/test.dart';

Matcher near(Point p) => isA<Point>()
    .having((q) => q.x, 'x', closeTo(p.x, 1e-9))
    .having((q) => q.y, 'y', closeTo(p.y, 1e-9));

void main() {
  test('a right-angle corner becomes an arc of the radius', () {
    final pieces = roundCorners(const [
      Point(0, 0),
      Point(50, 0),
      Point(50, 50),
    ], 10);
    expect(pieces, hasLength(3));
    expect(pieces[0].to, near(const Point(40, 0)));
    final arc = pieces[1] as ArcPiece;
    expect(arc.to, near(const Point(50, 10)));
    expect(arc.radius, closeTo(10, 1e-9));
    expect(arc.clockwise, isTrue);
    expect(pieces[2].to, const Point(50, 50));
  });

  test('a 45° corner keeps the same radius', () {
    final pieces = roundCorners(const [
      Point(0, 0),
      Point(50, 0),
      Point(80, -30),
      Point(120, -30),
    ], 10);
    final arc = pieces[1] as ArcPiece;
    expect(arc.radius, closeTo(10, 1e-9));
    expect(arc.clockwise, isFalse);
  });

  test('a corner between short pieces gets a smaller radius', () {
    final pieces = roundCorners(const [
      Point(0, 0),
      Point(50, 0),
      Point(50, 8),
      Point(100, 8),
    ], 10);
    expect((pieces[1] as ArcPiece).radius, closeTo(4, 1e-9));
    expect((pieces[3] as ArcPiece).radius, closeTo(4, 1e-9));
  });

  test('segments cross, touch, or run along each other', () {
    const h = Segment(Point(0, 5), Point(10, 5));
    expect(h.crosses(const Segment(Point(5, 0), Point(5, 10))), isTrue);
    expect(h.crosses(const Segment(Point(10, 0), Point(10, 10))), isTrue);
    expect(h.crosses(const Segment(Point(11, 0), Point(11, 10))), isFalse);
    expect(h.crosses(const Segment(Point(5, 5), Point(20, 5))), isFalse);
  });

  test('a segment enters a rectangle only through its inside', () {
    const rect = Rect.fromLTWH(0, 0, 10, 10);
    expect(
      const Segment(Point(-5, 5), Point(15, 5)).entersInterior(rect),
      isTrue,
    );
    expect(
      const Segment(Point(-5, 0), Point(15, 0)).entersInterior(rect),
      isFalse,
    );
    expect(
      const Segment(Point(10, 5), Point(20, 5)).entersInterior(rect),
      isFalse,
    );
  });

  test('directions', () {
    expect(const Segment(Point(0, 0), Point(5, 5)).isAllowedDirection, isTrue);
    expect(const Segment(Point(0, 0), Point(5, 6)).isAllowedDirection, isFalse);
  });
}
