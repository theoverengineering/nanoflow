import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/app.dart';
import 'package:nanoflow_ui/platform/shell.dart';
import 'package:nanoflow_ui/start/recent_graphs.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/golden.dart';

void main() {
  final home = Platform.environment['HOME']!;
  final now = DateTime(2026, 9, 21, 14);

  Future<void> pumpApp(
    WidgetTester tester,
    RecentGraphs recent, {
    Set<String> missing = const {},
  }) => pumpWindow(
    tester,
    NanoflowApp(
      recent: recent,
      shell: Shell(environment: const {}),
      pickFile: () async => null,
      exists: (path) => !missing.contains(path),
      now: () => now,
    ),
  );

  late RecentGraphs recent;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    recent = RecentGraphs(await SharedPreferences.getInstance());
  });

  testWidgets(
    'recently opened, the pointer on the newest card (docs/design/start.png)',
    (tester) async {
      await recent.opened('$home/sandbox/index.yaml', DateTime(2026, 9, 8, 11));
      await recent.opened(
        '$home/Projects/hr/onboarding.yaml',
        DateTime(2026, 9, 12, 16),
      );
      await recent.opened(
        '$home/work/deploy/release.yaml',
        DateTime(2026, 9, 20, 10),
      );
      await recent.opened(
        '$home/Projects/review/review.yaml',
        DateTime(2026, 9, 21, 12),
      );
      await pumpApp(
        tester,
        recent,
        missing: {'$home/Projects/hr/onboarding.yaml'},
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(
        location: tester.getCenter(find.text('~/Projects/review/review.yaml')),
      );
      await tester.pump();

      await expectGolden(tester, 'start_recent');
    },
  );

  testWidgets('nothing opened yet', (tester) async {
    await pumpApp(tester, recent);
    await expectGolden(tester, 'start_empty');
  });
}
