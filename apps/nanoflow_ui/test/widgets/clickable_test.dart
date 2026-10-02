import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/widgets/clickable.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    ),
  );

  testWidgets('a tap calls onTap', (tester) async {
    var taps = 0;
    await pump(
      tester,
      Clickable(onTap: () => taps++, child: const Text('Remove')),
    );
    await tester.tap(find.text('Remove'));
    expect(taps, 1);
  });

  testWidgets('shows the pointing hand', (tester) async {
    await pump(tester, Clickable(onTap: () {}, child: const Text('Remove')));
    final region = tester.widget<MouseRegion>(
      find
          .ancestor(of: find.text('Remove'), matching: find.byType(MouseRegion))
          .first,
    );
    expect(region.cursor, SystemMouseCursors.click);
  });

  testWidgets('hover builds the child for the pointer over it and gone', (
    tester,
  ) async {
    await pump(
      tester,
      Clickable.hover(
        onTap: () {},
        builder: (context, hovered) => Text(hovered ? 'over' : 'out'),
      ),
    );
    expect(find.text('out'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('out')));
    await tester.pump();
    expect(find.text('over'), findsOneWidget);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(find.text('out'), findsOneWidget);
  });
}
