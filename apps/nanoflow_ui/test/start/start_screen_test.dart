import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/start/recent_graphs.dart';
import 'package:nanoflow_ui/start/start_screen.dart';
import 'package:nanoflow_ui/theme.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/golden.dart';

void main() {
  final home = Platform.environment['HOME']!;
  final review = '$home/Projects/review/nanoflow.graph.json';
  final release = '$home/work/deploy/nanoflow.graph.json';
  final onboarding = '$home/Projects/hr/onboarding/nanoflow.graph.json';
  final now = DateTime(2026, 9, 21, 14);

  late RecentGraphs recent;
  late Set<String> missing;
  late List<String> opened;
  late DateTime clock;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    recent = RecentGraphs(await SharedPreferences.getInstance());
    missing = {};
    opened = [];
    clock = now;
  });

  /// The start screen with the open dialog answering [pick] (null:
  /// cancelled); what it opens goes to [opened].
  Future<void> pumpStart(WidgetTester tester, {String? pick}) => pumpScreen(
    tester,
    StartScreen(
      recent: recent,
      onOpen: (path, {store}) => opened.add(path),
      pickFile: () async => pick,
      exists: (path) => !missing.contains(path),
      now: () => clock,
    ),
  );

  test("names a graph's own file by its graph, and a package's by its "
      'directory', () {
    expect(
      graphTitle('$home/app/lib/src/generateIdeas.graph.json'),
      'generateIdeas',
    );
    expect(graphTitle(review), 'review');
  });

  testWidgets('recently opened graphs are listed newest first, by their '
      'directory, with path and time', (tester) async {
    await recent.opened(
      release,
      now.subtract(const Duration(days: 1, hours: 3)),
    );
    await recent.opened(review, now.subtract(const Duration(hours: 2)));
    await pumpStart(tester);

    expect(find.text('Recently opened'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('review'), findsOneWidget);
    expect(find.text('~/Projects/review/nanoflow.graph.json'), findsOneWidget);
    expect(find.text('Opened 2 hours ago'), findsOneWidget);
    expect(find.text('deploy'), findsOneWidget);
    expect(find.text('~/work/deploy/nanoflow.graph.json'), findsOneWidget);
    expect(find.text('Opened yesterday'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('review')).dy,
      lessThan(tester.getTopLeft(find.text('deploy')).dy),
    );
  });

  testWidgets('Open graph opens the chosen graph file', (tester) async {
    await pumpStart(tester, pick: review);

    await tester.tap(find.text('Open graph'));
    await tester.pumpAndSettle();

    expect(opened, [review]);
  });

  testWidgets('a chosen file that is not a graph file is not opened; a note '
      'says so', (tester) async {
    await pumpStart(tester, pick: '$home/Projects/review/package.json');

    await tester.tap(find.text('Open graph'));
    await tester.pump();

    expect(opened, isEmpty);
    expect(
      find.text('package.json is not a graph file: open a *.graph.json file'),
      findsOneWidget,
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('cancelling the open dialog opens nothing', (tester) async {
    await pumpStart(tester);

    await tester.tap(find.text('Open graph'));
    await tester.pumpAndSettle();

    expect(opened, isEmpty);
  });

  testWidgets('clicking a card opens its graph', (tester) async {
    await recent.opened(release, now.subtract(const Duration(days: 1)));
    await recent.opened(review, now.subtract(const Duration(hours: 2)));
    await pumpStart(tester);

    await tester.tap(find.text('deploy'));
    await tester.pumpAndSettle();

    expect(opened, [release]);
  });

  testWidgets(
    'a graph whose file is gone is dimmed, struck through and marked Missing',
    (tester) async {
      await recent.opened(onboarding, now.subtract(const Duration(days: 3)));
      await recent.opened(review, now.subtract(const Duration(hours: 2)));
      missing.add(onboarding);
      await pumpStart(tester);

      final name = tester.widget<Text>(find.text('onboarding')).style!;
      expect(name.decoration, TextDecoration.lineThrough);
      expect(name.color, AppColors.textFaint);
      expect(
        tester.widget<Text>(find.text('review')).style!.decoration,
        isNull,
      );
      expect(find.text('Missing'), findsOneWidget);
      expect(
        find.text('~/Projects/hr/onboarding/nanoflow.graph.json'),
        findsOneWidget,
      );
      expect(find.text('Remove'), findsOneWidget);
      // Only the graph still there says when it was opened.
      expect(find.textContaining('Opened'), findsOneWidget);
    },
  );

  testWidgets('clicking a missing graph does nothing', (tester) async {
    await recent.opened(onboarding, now.subtract(const Duration(days: 3)));
    missing.add(onboarding);
    await pumpStart(tester);

    await tester.tap(find.text('onboarding'));
    await tester.pumpAndSettle();

    expect(opened, isEmpty);
    expect(recent.graphs, [
      (
        path: onboarding,
        store: null,
        openedAt: now.subtract(const Duration(days: 3)),
      ),
    ]);
  });

  testWidgets('Remove takes a missing graph off the list', (tester) async {
    await recent.opened(onboarding, now.subtract(const Duration(days: 3)));
    await recent.opened(review, now.subtract(const Duration(hours: 2)));
    missing.add(onboarding);
    await pumpStart(tester);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('onboarding'), findsNothing);
    expect(find.text('1'), findsOneWidget);
    expect(recent.graphs.map((g) => g.path), [review]);
  });

  testWidgets(
    'a file that vanished while the list was shown is marked Missing, not opened',
    (tester) async {
      await recent.opened(review, now.subtract(const Duration(hours: 2)));
      await pumpStart(tester);
      expect(find.text('Missing'), findsNothing);

      missing.add(review);
      await tester.tap(find.text('review'));
      await tester.pumpAndSettle();

      expect(opened, isEmpty);
      expect(find.text('Missing'), findsOneWidget);
    },
  );

  testWidgets(
    'with nothing opened yet only the title, the button and the hint are shown',
    (tester) async {
      await pumpStart(tester);

      expect(find.text('Graphs'), findsOneWidget);
      expect(
        find.text('Open a graph file to watch its sessions live.'),
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
    await pumpStart(tester);
    expect(find.text('Opened 59 minutes ago'), findsOneWidget);

    clock = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));

    expect(find.text('Opened 1 hour ago'), findsOneWidget);
  });

  test(
    'the open dialog offers JSON files and answers with the chosen path',
    () async {
      final dialog = _FakeFileSelector();
      FileSelectorPlatform.instance = dialog;

      dialog.answer = '/Users/me/review/nanoflow.graph.json';
      expect(await pickGraphFile(), '/Users/me/review/nanoflow.graph.json');
      expect(dialog.accepted!.single.extensions, ['json']);

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
