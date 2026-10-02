import 'dart:math' as math;

/// A point on the canvas, in logical pixels; y grows downwards.
final class Point {
  const Point(this.x, this.y);

  final double x;
  final double y;

  Point operator +(Point other) => Point(x + other.x, y + other.y);

  Point operator -(Point other) => Point(x - other.x, y - other.y);

  Point operator *(double factor) => Point(x * factor, y * factor);

  double get length => math.sqrt(x * x + y * y);

  @override
  bool operator ==(Object other) =>
      other is Point && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '(${_short(x)}, ${_short(y)})';
}

/// An axis-aligned rectangle.
final class Rect {
  const Rect.fromLTRB(this.left, this.top, this.right, this.bottom);

  const Rect.fromLTWH(this.left, this.top, double width, double height)
    : right = left + width,
      bottom = top + height;

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;

  double get height => bottom - top;

  Point get center => Point((left + right) / 2, (top + bottom) / 2);

  /// Whether the open interiors of this and [other] share a point.
  bool overlaps(Rect other) =>
      left < other.right &&
      other.left < right &&
      top < other.bottom &&
      other.top < bottom;

  /// This rectangle grown by [delta] on every side.
  Rect inflate(double delta) =>
      Rect.fromLTRB(left - delta, top - delta, right + delta, bottom + delta);

  /// The smallest rectangle containing this and [other].
  Rect union(Rect other) => Rect.fromLTRB(
    math.min(left, other.left),
    math.min(top, other.top),
    math.max(right, other.right),
    math.max(bottom, other.bottom),
  );

  /// This rectangle moved by [offset].
  Rect shift(Point offset) => Rect.fromLTRB(
    left + offset.x,
    top + offset.y,
    right + offset.x,
    bottom + offset.y,
  );

  @override
  bool operator ==(Object other) =>
      other is Rect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() =>
      'Rect(${_short(left)}, ${_short(top)}, ${_short(right)}, ${_short(bottom)})';
}

/// A straight piece of a line between two points.
final class Segment {
  const Segment(this.a, this.b);

  final Point a;
  final Point b;

  double get length => (b - a).length;

  bool get isHorizontal => (a.y - b.y).abs() < _eps;

  bool get isVertical => (a.x - b.x).abs() < _eps;

  /// Whether the segment runs at 45° to the axes.
  bool get isDiagonal =>
      ((a.x - b.x).abs() - (a.y - b.y).abs()).abs() < _eps && length > _eps;

  /// Whether the segment runs along one of the three allowed directions:
  /// horizontal, vertical or 45°.
  bool get isAllowedDirection => isHorizontal || isVertical || isDiagonal;

  /// Whether this segment and [other] cross or touch at a point.
  ///
  /// Collinear overlapping segments do not count: they run along each other,
  /// which the spacing check catches.
  bool crosses(Segment other) {
    final d1 = _orient(other.a, other.b, a);
    final d2 = _orient(other.a, other.b, b);
    final d3 = _orient(a, b, other.a);
    final d4 = _orient(a, b, other.b);
    if (d1 == 0 && d2 == 0) return false;
    if (d1 * d2 > 0 || d3 * d4 > 0) return false;
    return true;
  }

  /// Whether the segment passes through the open interior of [rect].
  bool entersInterior(Rect rect) {
    // Clip the segment against the rectangle (Liang–Barsky).
    var t0 = 0.0;
    var t1 = 1.0;
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    bool clip(double p, double q) {
      if (p.abs() < 1e-12) return q > 0;
      final r = q / p;
      if (p < 0) {
        if (r > t1) return false;
        if (r > t0) t0 = r;
      } else {
        if (r < t0) return false;
        if (r < t1) t1 = r;
      }
      return true;
    }

    final inner = rect.inflate(-_eps);
    if (inner.width <= 0 || inner.height <= 0) return false;
    if (!clip(-dx, a.x - inner.left)) return false;
    if (!clip(dx, inner.right - a.x)) return false;
    if (!clip(-dy, a.y - inner.top)) return false;
    if (!clip(dy, inner.bottom - a.y)) return false;
    return t1 - t0 > 1e-9;
  }

  @override
  String toString() => '$a–$b';
}

/// One piece of a drawn path that starts where the previous piece ended.
sealed class PathPiece {
  const PathPiece(this.to);

  /// Where the piece ends.
  final Point to;
}

/// A straight line to [to].
final class LinePiece extends PathPiece {
  const LinePiece(super.to);

  @override
  String toString() => 'L$to';
}

/// A circular arc of [radius] to [to], turning clockwise on screen or not.
final class ArcPiece extends PathPiece {
  const ArcPiece(super.to, {required this.radius, required this.clockwise});

  final double radius;
  final bool clockwise;

  @override
  String toString() => 'A${_short(radius)}${clockwise ? 'cw' : 'ccw'}$to';
}

/// The polyline [points] with every corner rounded by [radius].
///
/// A corner gets a smaller radius where its segments are too short for the
/// full one: a corner never takes more than half of a segment it shares with
/// another corner, nor more than the whole end segment.
List<PathPiece> roundCorners(List<Point> points, double radius) {
  final pieces = <PathPiece>[];
  for (var i = 1; i < points.length - 1; i++) {
    final prev = points[i - 1];
    final corner = points[i];
    final next = points[i + 1];
    final inLength = (corner - prev).length;
    final outLength = (next - corner).length;
    if (inLength < _eps || outLength < _eps) continue;
    final d1 = (corner - prev) * (1 / inLength);
    final d2 = (next - corner) * (1 / outLength);
    final cross = d1.x * d2.y - d1.y * d2.x;
    if (cross.abs() < 1e-9) continue;
    final dot = (d1.x * d2.x + d1.y * d2.y).clamp(-1.0, 1.0);
    final turn = math.acos(dot);
    final tangentFactor = math.tan(turn / 2);
    final inRoom = i == 1 ? inLength : inLength / 2;
    final outRoom = i == points.length - 2 ? outLength : outLength / 2;
    final tangent = math.min(radius * tangentFactor, math.min(inRoom, outRoom));
    pieces.add(LinePiece(corner - d1 * tangent));
    pieces.add(
      ArcPiece(
        corner + d2 * tangent,
        radius: tangent / tangentFactor,
        clockwise: cross > 0,
      ),
    );
  }
  pieces.add(LinePiece(points.last));
  return pieces;
}

const double _eps = 1e-6;

int _orient(Point p, Point q, Point r) {
  final value = (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x);
  if (value.abs() < 1e-9) return 0;
  return value > 0 ? 1 : -1;
}

String _short(double value) => value == value.roundToDouble()
    ? '${value.toInt()}'
    : value.toStringAsFixed(2);
