import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/graph/canvas/copies_frame.dart';
import 'package:nanoflow_ui/graph/canvas/node_tile.dart';
import 'package:nanoflow_ui/graph/copy_switcher.dart';
import 'package:nanoflow_ui/graph/logs/effect_list.dart';
import 'package:nanoflow_ui/graph/logs/logs_panel.dart';
import 'package:nanoflow_ui/state/body_path.dart';
import 'package:nanoflow_ui/state/copies.dart';
import 'package:nanoflow_ui/state/graph_model.dart';
import 'package:nanoflow_ui/widgets/icons.dart' show PauseIcon;

import '../state/support.dart';
import 'canvas/support.dart';
import 'logs/support.dart';
import 'support.dart';

void main() {
  Finder chip(int? number) => find.byKey(CopySwitcher.chipKey(number));
  Finder footer() => find.byKey(CopiesFrameView.footerKey);
  String logsTitle(WidgetTester tester) =>
      textIn(tester, find.byKey(LogsPanel.titleKey));

  /// The screen of [copiesModel], the body of its copies drawn.
  Future<GraphModel> pumpCopies(
    WidgetTester tester, {
    GraphModel? model,
  }) async {
    final shown = await pumpGraphScreen(
      tester,
      path: inlineFile,
      model: model ?? copiesModel(),
      now: () => columnNow,
    );
    shown.open(const Opened('1'));
    await settle(tester);
    return shown;
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
    await settle(tester);
  }

  testWidgets('the copies tile says how many copies ran: ×3; Logs name '
      'the copy of each effect in them', (tester) async {
    await pumpGraphScreen(
      tester,
      path: inlineFile,
      model: copiesModel(),
      now: () => columnNow,
    );
    expect(
      find.descendant(
        of: find.byKey(NodeTile.keyOf('1')),
        matching: find.text('×3'),
      ),
      findsOneWidget,
    );
    expect(
      textIn(tester, find.byKey(EffectList.rowKey('c0c0-verify-4'))),
      startsWith('verify pkg 2'),
    );
  });

  testWidgets('the frame of the copies drawn: what they are over, how many, '
      'all of them, how many are done', (tester) async {
    await pumpCopies(tester);

    expect(find.text('each pkg in packages'), findsOneWidget);
    expect(find.text('×3 · in parallel'), findsOneWidget);
    expect(textIn(tester, find.byType(CopySwitcher)), 'all 1 2 3');
    expect(textIn(tester, footer()), 'done 1 of 3');
    // All selected: the effects say how many copies are on them now.
    expect(find.byKey(NodeTile.runningKeyOf('2')), findsOneWidget);
    expect(find.byKey(NodeTile.runningKeyOf('3')), findsOneWidget);
    expect(find.byKey(NodeTile.runningKeyOf('1')), findsNothing);
    // Logs names the copy of each effect.
    expect(logsTitle(tester), 'Logs 8 effects');
    expect(
      textIn(tester, find.byKey(EffectList.rowKey('c0c0-verify-4'))),
      startsWith('verify pkg 2'),
    );
  });

  testWidgets('a chip of a copy says how it stands, its hint over it', (
    tester,
  ) async {
    await pumpCopies(tester);

    CopyStatus? statusOf(int number) => tester
        .widget<CopySwitcher>(find.byType(CopySwitcher))
        .frame
        .copies
        .where((copy) => copy.number == number)
        .single
        .status;
    expect(
      [
        for (final n in [1, 2, 3]) statusOf(n),
      ],
      [CopyStatus.finished, CopyStatus.running, CopyStatus.running],
    );
    expect(
      find.ancestor(of: chip(2), matching: find.byTooltip('tool:uploaded')),
      findsOneWidget,
    );
  });

  testWidgets('a copy chosen: its path alone, copy 2 · now verify; Logs its '
      'effects; all goes back', (tester) async {
    final model = await pumpCopies(tester);

    await tap(tester, chip(2));

    expect(textIn(tester, footer()), 'pkg 2 · now verify');
    expect(logsTitle(tester), 'Logs pkg 2 · 2 effects');
    expect(model.selection.effectId, 'c0c0-verify-4');
    final marks = tester.widget<NodeTile>(find.byKey(NodeTile.keyOf('3')));
    expect(marks.marks!.effects, 0, reason: 'tool has not reached tag');
    expect(find.byKey(NodeTile.runningKeyOf('2')), findsNothing);
    final selected = tester.widget<Container>(
      find.descendant(of: chip(2), matching: find.byType(Container)).first,
    );
    expect(
      (selected.decoration! as BoxDecoration).color,
      const Color(0xFF3A3550),
    );

    await tap(tester, chip(null));
    expect(textIn(tester, footer()), 'done 1 of 3');
    expect(logsTitle(tester), 'Logs 8 effects');
  });

  testWidgets('more copies than chips: a list with a search and a filter', (
    tester,
  ) async {
    final graph = graphFileNamed('inline');
    final session = Journal(
      'm4ny-session',
      workflow: 'inPlace',
      graph: graph.toJson(),
      code: graph.fingerprint,
    );
    for (var i = 0; i < 20; i++) {
      session.effect(
        'upload',
        10 + i,
        end: i.isEven ? 100 : null,
        failed: i == 4,
        output: 'pkg$i',
        place: 'lib/inline.dart:10',
        key: 'upload#${i + 1}@e3b0',
        after: null,
      );
    }
    final model = await pumpCopies(
      tester,
      model: ownedModel(
        graph: graph,
        file: inlineFile,
        changes: session.changes,
        documents: {for (var i = 0; i < 20; i++) 'pkg$i': 'pkg$i'},
      ),
    );
    expect(chip(1), findsNothing);
    final list = find.byKey(CopySwitcher.listKey);
    expect(textIn(tester, find.byType(CopySwitcher)), 'all 20 copies');

    await tap(tester, list);
    expect(find.byKey(CopySwitcher.rowKey(1)), findsOneWidget);
    await tester.enterText(find.byKey(CopySwitcher.searchKey), 'pkg1');
    await tester.pump();
    // The copies whose upload finished hint at their package: pkg10,
    // pkg12 … pkg18 are copies 11, 13 … 19.
    expect(find.byKey(CopySwitcher.rowKey(11)), findsOneWidget);
    expect(find.byKey(CopySwitcher.rowKey(12)), findsNothing);
    expect(find.byKey(CopySwitcher.rowKey(3)), findsNothing);
    // A number finds its copy.
    await tester.enterText(find.byKey(CopySwitcher.searchKey), '12');
    await tester.pump();
    expect(find.byKey(CopySwitcher.rowKey(12)), findsOneWidget);
    expect(find.byKey(CopySwitcher.rowKey(11)), findsNothing);
    await tester.enterText(find.byKey(CopySwitcher.searchKey), '');
    await tester.tap(find.byKey(CopySwitcher.filterKey(CopyStatus.failed)));
    await tester.pump();
    expect(find.byKey(CopySwitcher.rowKey(5)), findsOneWidget);
    expect(find.byKey(CopySwitcher.rowKey(1)), findsNothing);

    await tap(tester, find.byKey(CopySwitcher.rowKey(5)));
    expect(textIn(tester, find.byType(CopySwitcher)), 'pkg 5 20 copies');
    expect(textIn(tester, footer()), 'pkg 5 · failed at upload');
    expect(model.selection.effectId, 'm4ny-upload-4');
  });

  testWidgets('in a session whose process is gone, a copy that was running '
      'is interrupted: its pause, where it stopped (owner spec §6)', (
    tester,
  ) async {
    final model = await pumpCopies(
      tester,
      model: ownedModel(
        graph: graphFileNamed('inline'),
        file: inlineFile,
        changes: (copiesSession()..processGone()).changes,
      ),
    );
    expect(
      find.descendant(of: chip(2), matching: find.byType(PauseIcon)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: chip(1), matching: find.byType(PauseIcon)),
      findsNothing,
    );
    await tap(tester, chip(2));
    expect(textIn(tester, footer()), 'pkg 2 · interrupted at verify');
    expect(model.selection.effectId, 'c0c0-verify-4');
  });

  testWidgets('more copies than chips, their process gone: the list filters '
      'the interrupted ones (owner spec §6)', (tester) async {
    final graph = graphFileNamed('inline');
    final many = Journal(
      'm4ny-session',
      workflow: 'inPlace',
      graph: graph.toJson(),
      code: graph.fingerprint,
    );
    for (var i = 0; i < 20; i++) {
      many.effect(
        'upload',
        10 + i,
        end: i.isEven ? 100 : null,
        place: 'lib/inline.dart:10',
        key: 'upload#${i + 1}@e3b0',
        after: null,
      );
    }
    many.processGone();
    await pumpCopies(
      tester,
      model: ownedModel(graph: graph, file: inlineFile, changes: many.changes),
    );
    await tap(tester, find.byKey(CopySwitcher.listKey));
    expect(
      find.byKey(CopySwitcher.filterKey(CopyStatus.running)),
      findsNothing,
    );
    await tester.tap(
      find.byKey(CopySwitcher.filterKey(CopyStatus.interrupted)),
    );
    await tester.pump();
    expect(find.byKey(CopySwitcher.rowKey(2)), findsOneWidget);
    expect(find.byKey(CopySwitcher.rowKey(1)), findsNothing);
  });

  testWidgets('copies in copies: the path of the copies chosen', (
    tester,
  ) async {
    final session = Journal(
      'n3st-session',
      workflow: 'nested',
      graph: copiesGraphJson(),
      code: 'sha256:copies-code',
    );
    for (final (i, pkg) in ['core', 'tool'].indexed) {
      session.effect(
        'fetch',
        1 + i,
        end: 3,
        place: copiesAt(27),
        key: 'f$pkg',
        after: null,
      );
      for (final target in ['arm', 'x64']) {
        session.effect(
          'build',
          4,
          place: copiesAt(30),
          key: 'b$pkg$target',
          after: 'f$pkg',
        );
      }
    }
    final model = await pumpGraphScreen(
      tester,
      model: ownedModel(graph: copiesGraphFile(), changes: session.changes),
      now: () => columnNow,
    );
    model.selectWorkflow('lib/copies.dart#nested');
    model.showSession('n3st-session');
    model.open(const Opened('1'));
    await settle(tester);
    await tap(tester, chip(2));
    model.open(const Opened('2'));
    await settle(tester);
    await tap(tester, chip(1));

    expect(textIn(tester, footer()), 'pkg 2 › target 1 · now build');
    expect(logsTitle(tester), 'Logs pkg 2 › target 1 · 1 effect');

    // All the copies of the frame around: none of these can be chosen.
    model.openLevel(1);
    await settle(tester);
    await tap(tester, chip(null));
    model.open(const Opened('2'));
    await settle(tester);
    expect(chip(1), findsNothing);
    expect(
      textIn(tester, find.byKey(CopySwitcher.chooseFirstKey)),
      'choose the outer pkg first',
    );
    expect(textIn(tester, footer()), 'done 0 of 4');
  });

  testWidgets('without a session the frame says what the copies are over, '
      'and no more', (tester) async {
    final model = await pumpCopies(tester);
    model.selection.showCurrentGraph();
    await settle(tester);

    expect(find.text('each pkg in packages'), findsOneWidget);
    expect(find.text('×n · in parallel'), findsOneWidget);
    expect(find.byType(CopySwitcher), findsNothing);
    expect(footer(), findsNothing);
  });
}
