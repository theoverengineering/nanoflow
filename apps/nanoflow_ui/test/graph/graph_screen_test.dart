import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/graph/canvas/graph_canvas.dart';
import 'package:nanoflow_ui/graph/graph_screen.dart';
import 'package:nanoflow_ui/graph/header.dart';
import 'package:nanoflow_ui/graph/sessions_column.dart';
import 'package:nanoflow_ui/platform/shell.dart';

import '../state/support.dart';
import '../support/golden.dart';
import 'support.dart';

void main() {
  testWidgets('lays out the header, the sessions column, the canvas and '
      'Logs as the mockup does', (tester) async {
    await pumpGraphScreen(tester);

    expect(
      tester.getRect(find.byType(GraphHeader)),
      const Rect.fromLTWH(0, 0, 1440, 48),
    );
    expect(
      tester.getRect(find.byType(SessionsColumn)),
      const Rect.fromLTRB(0, 48, 271, 900),
    );
    expect(
      tester.getRect(find.byType(GraphCanvas)),
      const Rect.fromLTRB(272, 48, 1440, 620),
    );
    expect(
      tester.getRect(find.byKey(GraphScreen.logsKey)),
      const Rect.fromLTRB(272, 621, 1440, 900),
    );
    expect(
      find.descendant(
        of: find.byKey(GraphScreen.logsKey),
        matching: find.text('Logs'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the borders of the sessions column and of Logs move', (
    tester,
  ) async {
    await pumpGraphScreen(tester);

    await tester.dragFrom(
      const Offset(271.5, 400),
      const Offset(60, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await tester.dragFrom(
      const Offset(800, 620.5),
      const Offset(0, -100),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(tester.getSize(find.byType(SessionsColumn)).width, 331);
    expect(
      tester.getRect(find.byType(GraphCanvas)),
      const Rect.fromLTRB(332, 48, 1440, 520),
    );
  });

  testWidgets('fits the smallest window with the sessions column at its '
      'narrowest and at its widest', (tester) async {
    // The window's least size: macos/Runner/MainFlutterWindow.swift.
    await pumpGraphScreen(tester, size: const Size(1100, 700));

    for (final by in [-200.0, 400.0]) {
      final border = tester.getTopRight(find.byType(SessionsColumn)).dx + 0.5;
      await tester.dragFrom(
        Offset(border, 400),
        Offset(by, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    expect(tester.getSize(find.byType(SessionsColumn)).width, 479);
  });

  testWidgets('opens the model of its graph file, and disposes it on leaving', (
    tester,
  ) async {
    final opened = <(String, Shell)>[];
    final shell = Shell();
    final model = mockupModel();
    await pumpScreen(
      tester,
      GraphScreen(
        path: reviewFile,
        shell: shell,
        onBack: () {},
        openModel: (file, shell) {
          opened.add((file, shell));
          return model;
        },
        now: () => Mockup.now,
      ),
    );
    expect(opened, [(reviewFile, shell)]);

    await tester.pumpWidget(const SizedBox());
    expect(sourceOf(model).disposed, isTrue);
  });

  testWidgets('disposes its model when the app is quit', (tester) async {
    final model = await pumpGraphScreen(tester);

    await tester.binding.handleRequestAppExit();
    expect(sourceOf(model).disposed, isTrue);

    // Leaving after that disposes nothing twice.
    await tester.pumpWidget(const SizedBox());
  });
}
