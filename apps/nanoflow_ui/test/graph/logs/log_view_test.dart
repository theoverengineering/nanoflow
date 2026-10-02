import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/graph/logs/log_view.dart';
import 'package:nanoflow_ui/graph/logs/mono_lines.dart';
import 'package:nanoflow_ui/graph/logs/step_details_pane.dart';
import 'package:nanoflow_ui/graph/logs/step_list.dart';
import 'package:nanoflow_ui/theme.dart';

import '../../state/support.dart';
import '../support.dart';
import 'support.dart';

void main() {
  Finder lines() => find.byKey(MonoLines.linesKey);
  Finder badge() => find.byKey(StepDetailsPane.followingKey);
  Finder line(String text) =>
      find.descendant(of: lines(), matching: find.text(text));

  ScrollPosition positionOf(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: lines(), matching: find.byType(Scrollable)).first,
      )
      .position;

  bool shown(WidgetTester tester, String text) =>
      shownWithin(tester, line(text), find.byType(MonoLines));

  String numbered(int from, int to) =>
      [for (var i = from; i <= to; i++) 'line $i\n'].join();

  Future<FakeFiles> pumpLog(WidgetTester tester, String log) async {
    final files = mockupFiles()..logs['e5f6-notify-0'] = log;
    await pumpGraphScreen(tester, model: mockupModel(files: files));
    await tester.pump();
    return files;
  }

  testWidgets('shows the step\'s log in monospace', (tester) async {
    await pumpGraphScreen(tester);

    for (final text in notifyLog.trimRight().split('\n')) {
      expect(line(text), findsOneWidget, reason: text);
      expect(tester.widget<Text>(line(text)).style!.fontFamily, AppText.mono);
    }
  });

  testWidgets('follows the tail of a running step\'s log, and says so', (
    tester,
  ) async {
    final files = await pumpLog(tester, numbered(1, 100));
    expect(shown(tester, 'line 100'), isTrue);
    expect(badge(), findsOneWidget);

    files.append('e5f6-notify-0', numbered(101, 120));
    await tester.pump();
    await tester.pump();
    expect(shown(tester, 'line 120'), isTrue);
    expect(badge(), findsOneWidget);
  });

  testWidgets('scrolled up, stops following and hides the badge; scrolled '
      'back down, follows again', (tester) async {
    final files = await pumpLog(tester, numbered(1, 100));

    await wheel(tester, lines(), -300);
    expect(badge(), findsNothing);
    final at = positionOf(tester).pixels;
    files.append('e5f6-notify-0', numbered(101, 120));
    await tester.pump();
    await tester.pump();
    expect(positionOf(tester).pixels, at);
    expect(shown(tester, 'line 120'), isFalse);

    await wheel(tester, lines(), 10000);
    expect(badge(), findsOneWidget);
    files.append('e5f6-notify-0', numbered(121, 130));
    await tester.pump();
    await tester.pump();
    expect(shown(tester, 'line 130'), isTrue);
  });

  testWidgets('opened again after it was scrolled up, follows the tail '
      'again', (tester) async {
    await pumpLog(tester, numbered(1, 1500));
    await wheel(tester, lines(), -300);
    expect(badge(), findsNothing);

    await tester.tap(find.byKey(StepDetailsPane.tabKey(StepTab.input)));
    await tester.pump();
    await tester.tap(find.byKey(StepDetailsPane.tabKey(StepTab.log)));
    // The text comes, then the view goes to its end.
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(
      textIn(tester, find.byKey(MonoLines.cutKey)),
      'Showing the last 1,000 of 1,500 lines Show all',
    );
    expect(shown(tester, 'line 1500'), isTrue);
    expect(badge(), findsOneWidget);
  });

  testWidgets('a finished step\'s log shows no badge', (tester) async {
    final files = mockupFiles()..logs['k7f2-collect-0'] = 'collected\n';
    await pumpGraphScreen(tester, model: mockupModel(files: files));

    await tester.tap(find.byKey(StepList.rowKey('k7f2-collect-0')));
    await tester.pump();
    await tester.pump();
    expect(line('collected'), findsOneWidget);
    expect(badge(), findsNothing);
  });

  testWidgets('a finished step that wrote nothing says so', (tester) async {
    await pumpGraphScreen(tester);

    await tester.tap(find.byKey(StepList.rowKey('k7f2-collect-0')));
    await tester.pump();
    await tester.pump();
    expect(find.text(LogView.nothing), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(LogView.nothing), findsOneWidget);
  });

  testWidgets('says why a log cannot be read', (tester) async {
    await pumpGraphScreen(
      tester,
      model: mockupModel(
        files: FakeFiles(
          logErrors: {'e5f6-notify-0': ArgumentError('no such step')},
        ),
      ),
    );

    expect(
      find.text('Could not read the log: Invalid argument(s): no such step'),
      findsOneWidget,
    );
  });

  testWidgets('keeps the log it has when a later read fails, and goes on', (
    tester,
  ) async {
    final files = await pumpLog(tester, notifyLog);

    files.fail('e5f6-notify-0', const FileSystemException('busy'));
    await tester.pump();
    expect(line('2 findings, 3 subscribers'), findsOneWidget);
    expect(find.textContaining('Could not read the log'), findsNothing);

    files.append('e5f6-notify-0', 'subscriber 3: sent\n');
    await tester.pump();
    await tester.pump();
    expect(line('subscriber 3: sent'), findsOneWidget);
  });

  testWidgets('stops reading the log of a step no longer shown', (
    tester,
  ) async {
    final files = await pumpLog(tester, notifyLog);
    expect(files.followed, ['e5f6-notify-0']);

    await tester.tap(find.byKey(StepDetailsPane.tabKey(StepTab.input)));
    await tester.pump();
    expect(files.followed, isEmpty);

    await tester.tap(find.byKey(StepDetailsPane.tabKey(StepTab.log)));
    await tester.pump();
    await tester.tap(find.byKey(StepList.rowKey('k7f2-collect-0')));
    await tester.pump();
    expect(files.followed, ['k7f2-collect-0']);
  });

  testWidgets('a big log shows its tail, and Show all all of it', (
    tester,
  ) async {
    await pumpLog(tester, numbered(1, 1500));

    final cut = find.byKey(MonoLines.cutKey);
    expect(
      textIn(tester, cut),
      'Showing the last 1,000 of 1,500 lines Show all',
    );
    await wheel(tester, lines(), -1e6);
    expect(shown(tester, 'line 501'), isTrue);
    expect(line('line 500'), findsNothing);

    await tester.tap(find.descendant(of: cut, matching: find.text('Show all')));
    await tester.pump();
    await tester.pump();
    expect(cut, findsNothing);
    await wheel(tester, lines(), -1e6);
    expect(shown(tester, 'line 1'), isTrue);
  });

  testWidgets('a big document shows its start, and Show all all of it', (
    tester,
  ) async {
    final files = mockupFiles()
      ..documents['report-2'] = [for (var i = 1; i <= 1500; i++) 'f$i'];
    await pumpGraphScreen(tester, model: mockupModel(files: files));

    await tester.tap(find.byKey(StepDetailsPane.tabKey(StepTab.input)));
    await tester.pump();
    await tester.pump();
    final cut = find.byKey(MonoLines.cutKey);
    expect(
      textIn(tester, cut),
      'Showing the first 1,000 of 1,502 lines Show all',
    );
    expect(shown(tester, '[') && shown(tester, '  "f1",'), isTrue);

    await tester.tap(find.descendant(of: cut, matching: find.text('Show all')));
    await tester.pump();
    expect(cut, findsNothing);
    await wheel(tester, lines(), 1e6);
    expect(shown(tester, '  "f1500"'), isTrue);
  });

  testWidgets('a long line does not wrap: it scrolls sideways', (tester) async {
    final long = List.filled(400, 'x').join();
    await pumpLog(tester, '$long\n');

    expect(tester.getSize(line(long)).height, lessThan(20));
    final sideways = tester
        .state<ScrollableState>(
          find.ancestor(of: lines(), matching: find.byType(Scrollable)).first,
        )
        .position;
    expect(sideways.axis, Axis.horizontal);
    expect(sideways.maxScrollExtent, greaterThan(0));
  });
}
