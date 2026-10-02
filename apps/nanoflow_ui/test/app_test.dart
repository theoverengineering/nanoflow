import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/app.dart';
import 'package:nanoflow_ui/graph/graph_screen.dart';
import 'package:nanoflow_ui/platform/shell.dart';
import 'package:nanoflow_ui/start/recent_graphs.dart';
import 'package:nanoflow_ui/start/start_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'graph/canvas/support.dart';
import 'support/golden.dart';

void main() {
  final home = Platform.environment['HOME']!;
  final review = '$home/Projects/review/review.yaml';
  final release = '$home/work/deploy/release.yaml';
  final now = DateTime(2026, 9, 21, 14);

  testWidgets('the app starts on the start screen, goes to a graph and back', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final recent = RecentGraphs(await SharedPreferences.getInstance());
    await recent.opened(review, now.subtract(const Duration(days: 2)));
    await recent.opened(release, now.subtract(const Duration(hours: 1)));
    await pumpWindow(
      tester,
      NanoflowApp(
        recent: recent,
        shell: Shell(environment: const {}),
        pickFile: () async => null,
        exists: (_) => true,
        now: () => now,
        openModel: (_, _) => ownedModel(),
      ),
    );
    expect(find.byType(StartScreen), findsOneWidget);

    await tester.tap(find.text('review.yaml'));
    await tester.pumpAndSettle();
    expect(find.byType(StartScreen), findsNothing);
    expect(find.byType(GraphScreen), findsOneWidget);
    expect(find.text('~/Projects/review'), findsOneWidget);

    await tester.tap(find.text('Graphs'));
    await tester.pumpAndSettle();
    expect(find.byType(GraphScreen), findsNothing);
    expect(find.byType(StartScreen), findsOneWidget);
    expect(find.text('Opened just now'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('review.yaml')).dy,
      lessThan(tester.getTopLeft(find.text('release.yaml')).dy),
    );
  });
}
