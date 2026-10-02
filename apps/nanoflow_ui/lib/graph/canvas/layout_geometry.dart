import 'dart:ui';

import '../../layout/layout.dart' as layout;

/// The layout's points as Flutter's.
extension LayoutPoint on layout.Point {
  Offset toOffset() => Offset(x, y);
}

/// The layout's rectangles as Flutter's.
extension LayoutRect on layout.Rect {
  Rect toRect() => Rect.fromLTRB(left, top, right, bottom);
}
