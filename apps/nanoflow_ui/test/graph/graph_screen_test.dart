import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/graph/graph_screen.dart';
import 'package:nanoflow_ui/platform/shell.dart';

import '../support/golden.dart';

void main() {
  final home = Platform.environment['HOME']!;

  testWidgets('the header names the graph file and its directory', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      GraphScreen(
        path: '$home/Projects/review/review.yaml',
        shell: Shell(environment: const {}),
        onBack: () {},
      ),
    );

    expect(find.text('Graphs'), findsOneWidget);
    expect(find.text('review.yaml'), findsOneWidget);
    expect(find.text('~/Projects/review'), findsOneWidget);
  });

  testWidgets('Graphs leads back', (tester) async {
    var backs = 0;
    await pumpScreen(
      tester,
      GraphScreen(
        path: '$home/Projects/review/review.yaml',
        shell: Shell(environment: const {}),
        onBack: () => backs++,
      ),
    );

    await tester.tap(find.text('Graphs'));
    expect(backs, 1);
  });
}
