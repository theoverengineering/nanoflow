import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/app.dart';

/// The window the mockups in docs/design/ are drawn for.
const mockupWindow = Size(1440, 900);

/// Pumps [app] (a whole MaterialApp) into a [size] window at 2× — the
/// density of the mockup PNGs.
Future<void> pumpWindow(
  WidgetTester tester,
  Widget app, {
  Size size = mockupWindow,
}) async {
  tester.view
    ..physicalSize = size * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
}

/// Pumps [screen] in the app's MaterialApp, as [pumpWindow] does.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  Size size = mockupWindow,
}) => pumpWindow(tester, appFrame(home: screen), size: size);

/// Compares the whole window with test/goldens/[name].png; regenerate with
/// `flutter test --update-goldens`.
Future<void> expectGolden(WidgetTester tester, String name) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('$name.png'));
