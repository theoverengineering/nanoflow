import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/graph/split_view.dart';

import '../support/golden.dart';

void main() {
  const first = Key('first');
  const second = Key('second');

  /// Side by side, the first pane 272 px with its border line, 200 to 480.
  Widget columns({double minOther = 400}) => SplitView(
    axis: Axis.horizontal,
    sized: SplitPane.first,
    extent: 272,
    minExtent: 200,
    maxExtent: 480,
    minOther: minOther,
    border: const Color(0xFF2B2C30),
    first: const SizedBox.expand(key: first),
    second: const SizedBox.expand(key: second),
  );

  /// One over the other, the second pane 280 px with its border line, at
  /// least 120, the first at least 200; [fixedExtent] while folded.
  Widget rows({double? fixedExtent}) => SplitView(
    axis: Axis.vertical,
    sized: SplitPane.second,
    extent: 280,
    minExtent: 120,
    maxExtent: double.infinity,
    minOther: 200,
    border: const Color(0xFF34353A),
    fixedExtent: fixedExtent,
    first: const SizedBox.expand(key: first),
    second: const SizedBox.expand(key: second),
  );

  Future<void> drag(WidgetTester tester, Offset from, Offset by) =>
      tester.dragFrom(from, by, kind: PointerDeviceKind.mouse);

  testWidgets('the sized pane has its extent with the border line', (
    tester,
  ) async {
    await pumpScreen(tester, columns());

    expect(
      tester.getRect(find.byKey(first)),
      const Rect.fromLTWH(0, 0, 271, 900),
    );
    expect(
      tester.getRect(find.byKey(second)),
      const Rect.fromLTRB(272, 0, 1440, 900),
    );
  });

  testWidgets('dragging the border moves it with the pointer', (tester) async {
    await pumpScreen(tester, columns());

    await drag(tester, const Offset(271.5, 300), const Offset(100, 0));
    await tester.pump();

    expect(tester.getSize(find.byKey(first)).width, 371);
    expect(tester.getTopLeft(find.byKey(second)).dx, 372);
  });

  testWidgets('the border stops at the least and the most extent', (
    tester,
  ) async {
    await pumpScreen(tester, columns());

    await drag(tester, const Offset(271.5, 300), const Offset(400, 0));
    await tester.pump();
    expect(tester.getSize(find.byKey(first)).width, 479);

    await drag(tester, const Offset(479.5, 300), const Offset(-500, 0));
    await tester.pump();
    expect(tester.getSize(find.byKey(first)).width, 199);
  });

  testWidgets('the other pane keeps its least extent', (tester) async {
    await pumpScreen(tester, columns(minOther: 1200));

    expect(tester.getSize(find.byKey(second)).width, 1200);

    await drag(tester, const Offset(239.5, 300), const Offset(100, 0));
    await tester.pump();
    expect(tester.getSize(find.byKey(second)).width, 1200);
  });

  testWidgets('a pane at the end grows as the border goes towards the start', (
    tester,
  ) async {
    await pumpScreen(tester, rows());

    expect(
      tester.getRect(find.byKey(first)),
      const Rect.fromLTRB(0, 0, 1440, 620),
    );
    expect(
      tester.getRect(find.byKey(second)),
      const Rect.fromLTRB(0, 621, 1440, 900),
    );

    await drag(tester, const Offset(700, 620.5), const Offset(0, -100));
    await tester.pump();
    expect(tester.getSize(find.byKey(second)).height, 379);
    expect(tester.getSize(find.byKey(first)).height, 520);

    await drag(tester, const Offset(700, 520.5), const Offset(0, -600));
    await tester.pump();
    expect(tester.getSize(find.byKey(first)).height, 200);
  });

  testWidgets('the border shows the resize pointer', (tester) async {
    await pumpScreen(tester, columns());

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(271.5, 300));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.resizeColumn,
    );
  });

  testWidgets('a fixed extent holds the sized pane and the border; then it '
      'comes back to where it was dragged', (tester) async {
    await pumpScreen(tester, rows());
    await drag(tester, const Offset(700, 620.5), const Offset(0, -100));
    await tester.pump();

    await pumpScreen(tester, rows(fixedExtent: 39));
    expect(
      tester.getRect(find.byKey(second)),
      const Rect.fromLTRB(0, 862, 1440, 900),
    );
    await drag(tester, const Offset(700, 861.5), const Offset(0, -100));
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(second)).dy, 862);

    await pumpScreen(tester, rows());
    expect(tester.getTopLeft(find.byKey(second)).dy, 521);
  });
}
