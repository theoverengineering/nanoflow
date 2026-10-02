import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/app.dart';
import 'package:nanoflow_ui/graph/graph_screen.dart';
import 'package:nanoflow_ui/platform/shell.dart';
import 'package:nanoflow_ui/start/recent_graphs.dart';
import 'package:nanoflow_ui/start/start_screen.dart';
import 'package:nanoflow_ui/theme.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/golden.dart';

void main() {
  final home = Platform.environment['HOME']!;
  final review = '$home/Projects/review/review.yaml';
  final release = '$home/work/deploy/release.yaml';
  final onboarding = '$home/Projects/hr/onboarding.yaml';
  final now = DateTime(2026, 9, 21, 14);

  late RecentGraphs recent;
  late Set<String> missing;
  late DateTime clock;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    recent = RecentGraphs(await SharedPreferences.getInstance());
    missing = {};
    clock = now;
  });

  /// The app with the open dialog answering [pick] (null: cancelled).
  Future<void> pumpApp(WidgetTester tester, {String? pick}) => pumpWindow(
    tester,
    NanoflowApp(
      recent: recent,
      shell: Shell(environment: const {}),
      pickFile: () async => pick,
      exists: (path) => !missing.contains(path),
      now: () => clock,
    ),
  );

  bool onStartScreen() =>
      find.byType(StartScreen).evaluate().isNotEmpty &&
      find.byType(GraphScreen).evaluate().isEmpty;

  testWidgets(
    'recently opened graphs are listed newest first with path and time',
    (tester) async {
      await recent.opened(
        release,
        now.subtract(const Duration(days: 1, hours: 3)),
      );
      await recent.opened(review, now.subtract(const Duration(hours: 2)));
      await pumpApp(tester);

      expect(find.text('Recently opened'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('review.yaml'), findsOneWidget);
      expect(find.text('~/Projects/review/review.yaml'), findsOneWidget);
      expect(find.text('Opened 2 hours ago'), findsOneWidget);
      expect(find.text('release.yaml'), findsOneWidget);
      expect(find.text('~/work/deploy/release.yaml'), findsOneWidget);
      expect(find.text('Opened yesterday'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('review.yaml')).dy,
        lessThan(tester.getTopLeft(find.text('release.yaml')).dy),
      );
    },
  );

  testWidgets('Open graph opens the chosen file and lists it on top', (
    tester,
  ) async {
    await recent.opened(release, now.subtract(const Duration(days: 1)));
    await pumpApp(tester, pick: review);

    await tester.tap(find.text('Open graph'));
    await tester.pumpAndSettle();

    expect(onStartScreen(), isFalse);
    expect(tester.widget<GraphScreen>(find.byType(GraphScreen)).path, review);
    expect(recent.graphs.first, (path: review, openedAt: now));
  });

  testWidgets('cancelling the open dialog stays on the start screen', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Open graph'));
    await tester.pumpAndSettle();

    expect(onStartScreen(), isTrue);
    expect(recent.graphs, isEmpty);
  });

  testWidgets('clicking a card opens its graph and moves it on top', (
    tester,
  ) async {
    await recent.opened(release, now.subtract(const Duration(days: 1)));
    await recent.opened(review, now.subtract(const Duration(hours: 2)));
    await pumpApp(tester);

    await tester.tap(find.text('release.yaml'));
    await tester.pumpAndSettle();

    expect(tester.widget<GraphScreen>(find.byType(GraphScreen)).path, release);
    expect(recent.graphs.map((g) => g.path), [release, review]);
    expect(recent.graphs.first.openedAt, now);
  });

  testWidgets(
    'a graph whose file is gone is dimmed, struck through and marked Missing',
    (tester) async {
      await recent.opened(onboarding, now.subtract(const Duration(days: 3)));
      await recent.opened(review, now.subtract(const Duration(hours: 2)));
      missing.add(onboarding);
      await pumpApp(tester);

      final name = tester.widget<Text>(find.text('onboarding.yaml')).style!;
      expect(name.decoration, TextDecoration.lineThrough);
      expect(name.color, AppColors.textFaint);
      expect(
        tester.widget<Text>(find.text('review.yaml')).style!.decoration,
        isNull,
      );
      expect(find.text('Missing'), findsOneWidget);
      expect(find.text('~/Projects/hr/onboarding.yaml'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      // Only the graph still there says when it was opened.
      expect(find.textContaining('Opened'), findsOneWidget);
    },
  );

  testWidgets('clicking a missing graph does nothing', (tester) async {
    await recent.opened(onboarding, now.subtract(const Duration(days: 3)));
    missing.add(onboarding);
    await pumpApp(tester);

    await tester.tap(find.text('onboarding.yaml'));
    await tester.pumpAndSettle();

    expect(onStartScreen(), isTrue);
    expect(recent.graphs, [
      (path: onboarding, openedAt: now.subtract(const Duration(days: 3))),
    ]);
  });

  testWidgets('Remove takes a missing graph off the list', (tester) async {
    await recent.opened(onboarding, now.subtract(const Duration(days: 3)));
    await recent.opened(review, now.subtract(const Duration(hours: 2)));
    missing.add(onboarding);
    await pumpApp(tester);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(onStartScreen(), isTrue);
    expect(find.text('onboarding.yaml'), findsNothing);
    expect(find.text('1'), findsOneWidget);
    expect(recent.graphs.map((g) => g.path), [review]);
  });

  testWidgets(
    'a file that vanished while the list was shown is marked Missing, not opened',
    (tester) async {
      await recent.opened(review, now.subtract(const Duration(hours: 2)));
      await pumpApp(tester);
      expect(find.text('Missing'), findsNothing);

      missing.add(review);
      await tester.tap(find.text('review.yaml'));
      await tester.pumpAndSettle();

      expect(onStartScreen(), isTrue);
      expect(find.text('Missing'), findsOneWidget);
    },
  );

  testWidgets(
    'with nothing opened yet only the title, the button and the hint are shown',
    (tester) async {
      await pumpApp(tester);

      expect(find.text('Graphs'), findsOneWidget);
      expect(
        find.text('Open a graph file to watch its runs live.'),
        findsOneWidget,
      );
      expect(find.text('Open graph'), findsOneWidget);
      expect(find.text('Recently opened'), findsNothing);
    },
  );

  testWidgets('when a graph was opened keeps up while the screen stays open', (
    tester,
  ) async {
    await recent.opened(review, now.subtract(const Duration(minutes: 59)));
    await pumpApp(tester);
    expect(find.text('Opened 59 minutes ago'), findsOneWidget);

    clock = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));

    expect(find.text('Opened 1 hour ago'), findsOneWidget);
  });

  test(
    'the open dialog offers YAML files and answers with the chosen path',
    () async {
      final dialog = _FakeFileSelector();
      FileSelectorPlatform.instance = dialog;

      dialog.answer = '/Users/me/review.yaml';
      expect(await pickGraphFile(), '/Users/me/review.yaml');
      expect(dialog.accepted!.single.extensions, ['yaml', 'yml']);

      dialog.answer = null;
      expect(await pickGraphFile(), isNull);
    },
  );
}

class _FakeFileSelector extends FileSelectorPlatform
    with MockPlatformInterfaceMixin {
  String? answer;
  List<XTypeGroup>? accepted;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    accepted = acceptedTypeGroups;
    return answer == null ? null : XFile(answer!);
  }
}
