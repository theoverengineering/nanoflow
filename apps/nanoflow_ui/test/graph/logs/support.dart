// What the tests of the Logs panel look at.

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The text under [finder], each piece once, in order, spaces made single.
String textIn(WidgetTester tester, Finder finder) => tester
    .widgetList<RichText>(
      find.descendant(of: finder, matching: find.byType(RichText)),
    )
    .map((text) => text.text.toPlainText())
    .join(' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Whether [inner] is built in view and lies wholly inside [outer] on the
/// screen.
bool shownWithin(WidgetTester tester, Finder inner, Finder outer) {
  if (inner.evaluate().isEmpty) return false;
  final rect = tester.getRect(inner);
  final room = tester.getRect(outer);
  return room.intersect(rect) == rect;
}

/// Turns the mouse wheel over [finder] by [dy] pixels.
Future<void> wheel(WidgetTester tester, Finder finder, double dy) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(tester.getCenter(finder)));
  await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
  await tester.pump();
}
