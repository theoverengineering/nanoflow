import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/graph/canvas/graph_canvas.dart';
import 'package:nanoflow_ui/graph/canvas/node_tile.dart';
import 'package:nanoflow_ui/graph/canvas/tile_marks.dart' show StateBadge;
import 'package:nanoflow_ui/graph/graph_notes.dart';
import 'package:nanoflow_ui/graph/graph_screen.dart';
import 'package:nanoflow_ui/graph/header.dart';
import 'package:nanoflow_ui/graph/logs/effect_bar.dart' show EffectIcon;
import 'package:nanoflow_ui/graph/logs/effect_list.dart';
import 'package:nanoflow_ui/graph/session_bar.dart';
import 'package:nanoflow_ui/graph/sessions_column.dart';
import 'package:nanoflow_ui/platform/shell.dart';
import 'package:nanoflow_ui/state/graph_marks.dart' show NodeState;
import 'package:nanoflow_ui/state/visits.dart' show StartOutcome;
import 'package:nanoflow_ui/widgets/spinner.dart';

import '../state/support.dart';
import '../support/golden.dart';
import 'canvas/support.dart';
import 'support.dart';

void main() {
  Finder tile(String id) => find.byKey(NodeTile.tileKeyOf(id));

  Finder inHeader(Finder finder) =>
      find.descendant(of: find.byType(GraphHeader), matching: finder);

  /// The names under the tiles on the canvas.
  List<String> names(WidgetTester tester) => [
    for (final node in tester.widgetList<NodeTile>(find.byType(NodeTile)))
      ?node.node.name,
  ];

  Future<void> doubleTap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('lays out the header, the sessions column, and the canvas '
      'over the Logs panel', (tester) async {
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
  });

  testWidgets('the border of the sessions column moves', (tester) async {
    await pumpGraphScreen(tester);

    await tester.dragFrom(
      const Offset(271.5, 400),
      const Offset(60, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(tester.getSize(find.byType(SessionsColumn)).width, 331);
    expect(
      tester.getRect(find.byType(GraphCanvas)),
      const Rect.fromLTRB(332, 48, 1440, 620),
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

  group('a double click', () {
    testWidgets('on a call draws its function\'s body under a crumb of it; '
        'the workflow\'s crumb draws the workflow again', (tester) async {
      final model = await pumpGraphScreen(tester);
      expect(names(tester), contains('publish()'));

      await doubleTap(tester, tile('5'));
      await settle(tester);
      expect(names(tester), ['upload', 'verify', '!ok', 'rollback']);
      expect(model.canvas.levels, hasLength(2));
      expect(inHeader(find.text('publish()')), findsOneWidget);

      await tester.tap(inHeader(find.text('release')));
      await settle(tester);
      expect(names(tester), contains('publish()'));
      expect(names(tester), isNot(contains('upload')));
    });

    testWidgets('on copies draws the body of a copy', (tester) async {
      final model = await pumpGraphScreen(
        tester,
        model: ownedModel(
          graph: GraphFile.fromJson({
            ...graphFileNamed('inline').toJson(),
            'workflows': ['lib/inline.dart#inPlace'],
          }),
        ),
      );
      expect(names(tester), ['pkg in packages', 'announce']);

      await doubleTap(tester, tile('1'));
      await settle(tester);
      expect(names(tester), ['upload', 'verify', 'tag']);
      expect(inHeader(find.text('pkg in packages')), findsOneWidget);
      expect(model.canvas.levels.last.title, 'pkg in packages');
    });

    testWidgets('on a call of an interface method offers its '
        'implementations', (tester) async {
      await pumpGraphScreen(
        tester,
        model: ownedModel(graph: graphFileNamed('interfaces')),
      );
      final call = tester
          .widgetList<NodeTile>(find.byType(NodeTile))
          .firstWhere((t) => t.node.node is CallNode)
          .node
          .id;

      await doubleTap(tester, tile(call));
      await tester.pumpAndSettle();
      final menu = find.byType(PopupMenuItem<String>);
      expect(menu, findsNWidgets(2));
      expect(
        find.descendant(of: menu, matching: find.text('ChatNotifier.notify()')),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(of: menu, matching: find.text('MailNotifier.notify()')),
      );
      await tester.pumpAndSettle();
      expect(inHeader(find.text('MailNotifier.notify()')), findsOneWidget);
      expect(names(tester), hasLength(2));
    });

    testWidgets('on an effect opens nothing', (tester) async {
      final model = await pumpGraphScreen(tester);
      await doubleTap(tester, tile('1'));
      await settle(tester);
      expect(model.canvas.levels, hasLength(1));
    });
  });

  testWidgets('a session is drawn on its own graph, which opens the same way', (
    tester,
  ) async {
    // The session's snapshot calls ship() from release; the graph file
    // calls publish().
    final snapshot = graphFileNamed('release').toJson();
    final functions = snapshot['functions']! as Map<String, Object?>;
    final publish = functions.remove('lib/publish.dart#publish')!;
    functions['lib/publish.dart#ship'] = {
      ...publish as Map<String, Object?>,
      'name': 'ship',
    };
    final body =
        (functions['lib/release.dart#release']! as Map)['body']! as Map;
    for (final node in body['nodes']! as List) {
      if ((node as Map)['kind'] == 'call') {
        node['functions'] = ['lib/publish.dart#ship'];
      }
    }
    final model = await pumpGraphScreen(
      tester,
      model: ownedModel(
        changes: changesOf([
          Journal('r1r1-session', workflow: 'release', graph: snapshot),
        ]),
      ),
    );
    expect(model.selection.sessionId, 'r1r1-session');
    expect(names(tester), contains('ship()'));

    await doubleTap(tester, tile('5'));
    await settle(tester);
    expect(inHeader(find.text('ship()')), findsOneWidget);
    expect(names(tester), ['upload', 'verify', '!ok', 'rollback']);

    // The graph file has no ship(): Current graph is drawn from the top.
    model.selection.showCurrentGraph();
    await settle(tester);
    expect(names(tester), contains('publish()'));
  });

  group('a session whose process is gone (owner spec §6)', () {
    Finder inCard(Finder finder) => find.descendant(
      of: find.byKey(SessionsColumn.cardKey('a1b2-session')),
      matching: finder,
    );
    Finder inBar(Finder finder) =>
        find.descendant(of: find.byType(SessionBar), matching: finder);
    Finder notify() => find.byKey(NodeTile.keyOf('7'));
    Finder notifyRow() => find.byKey(EffectList.rowKey('a1b2-notify-5'));
    Finder inside(Finder of, Type type) =>
        find.descendant(of: of, matching: find.byType(type));
    NodeState? notifyState(WidgetTester tester) =>
        tester.widget<NodeTile>(notify()).marks?.state;
    StartOutcome notifyIcon(WidgetTester tester) =>
        tester.widget<EffectIcon>(inside(notifyRow(), EffectIcon)).status;

    void expectRunning(WidgetTester tester) {
      expect(inCard(find.text('Running for 12m 26s')), findsOneWidget);
      expect(inBar(find.text('running 12m 26s')), findsOneWidget);
      expect(notifyState(tester), NodeState.running);
      expect(inside(notify(), Spinner), findsOneWidget);
      expect(notifyIcon(tester), StartOutcome.running);
      expect(find.text('following tail'), findsOneWidget);
    }

    void expectInterrupted(WidgetTester tester) {
      expect(inCard(find.text('Interrupted after 10m 12s')), findsOneWidget);
      expect(inBar(find.text('interrupted after 10m 12s')), findsOneWidget);
      expect(notifyState(tester), NodeState.interrupted);
      expect(inside(notify(), Spinner), findsNothing);
      expect(inside(notify(), StateBadge), findsOneWidget);
      expect(notifyIcon(tester), StartOutcome.interrupted);
      expect(inside(notifyRow(), Spinner), findsNothing);
      // Its log grows no more: nothing to follow.
      expect(find.text('following tail'), findsNothing);
    }

    testWidgets('is interrupted on its card, its bar, the node of the effect '
        'that was running and its row in Logs', (tester) async {
      await pumpReview(
        tester,
        model: reviewModel(
          more: [
            OwnerChanged(
              sessionId: 'a1b2-session',
              owner: testOwner,
              alive: false,
            ),
          ],
        ),
      );
      expectInterrupted(tester);
    });

    testWidgets('is interrupted the moment the reader tells, with nothing '
        'else coming; runs again once a process owns it again', (tester) async {
      final more = StreamController<Change>();
      addTearDown(more.close);
      await pumpReview(
        tester,
        model: ownedModel(
          graph: graphFileNamed('review'),
          file: reviewFile,
          changes: reviewSession().changes,
          more: more.stream,
          documents: reviewDocuments,
          files: reviewFiles(),
        ),
      );
      expectRunning(tester);

      Future<void> tell(Owner? owner, bool? alive) async {
        more.add(
          OwnerChanged(sessionId: 'a1b2-session', owner: owner, alive: alive),
        );
        await settle(tester);
      }

      await tell(testOwner, true);
      expectRunning(tester);
      await tell(testOwner, null);
      expectRunning(tester);

      await tell(testOwner, false);
      expectInterrupted(tester);

      await tell(Owner(pid: 4343, started: at(700)), true);
      expectRunning(tester);
    });
  });

  testWidgets('the notes over the canvas stay under the session bar', (
    tester,
  ) async {
    await pumpGraphScreen(
      tester,
      model: ownedModel(
        changes: changesOf([
          Journal('r1r1-session', workflow: 'release', snapshot: false),
        ]),
      ),
    );
    final bar = tester.getRect(find.byType(SessionBar));
    expect(bar.height, greaterThan(0));
    final notes = tester.getRect(
      find.descendant(
        of: find.byType(GraphNotes),
        matching: find.text('Session has no snapshot'),
      ),
    );
    expect(notes.top, greaterThan(bar.bottom));
  });

  testWidgets('opens the model of its graph file, and disposes it on leaving', (
    tester,
  ) async {
    final opened = <String>[];
    final model = ownedModel(file: releaseFile);
    await pumpScreen(
      tester,
      GraphScreen(
        path: releaseFile,
        shell: Shell(),
        onBack: () {},
        openModel: (file, {store, session}) {
          opened.add(file);
          return model;
        },
        now: () => at(100000),
      ),
    );
    expect(opened, [releaseFile]);

    await tester.pumpWidget(const SizedBox());
    expect(graphFileOf(model).disposed, isTrue);
  });

  testWidgets('lets the app quit once its feed has stopped, and disposes '
      'its model then', (tester) async {
    // A reader's feed stops once it no longer watches the processes that own
    // sessions; the app may not end before that.
    final stopped = Completer<void>();
    final more = StreamController<Change>(onCancel: () => stopped.future);
    final model = await pumpGraphScreen(
      tester,
      model: ownedModel(file: releaseFile, more: more.stream),
    );

    AppExitResponse? response;
    unawaited(tester.binding.handleRequestAppExit().then((r) => response = r));
    await tester.pump();
    expect(more.hasListener, isFalse);
    expect(response, isNull);
    // The screen still draws it meanwhile.
    expect(graphFileOf(model).disposed, isFalse);

    stopped.complete();
    await tester.pump();
    expect(response, AppExitResponse.exit);
    expect(graphFileOf(model).disposed, isTrue);

    // Leaving after that disposes nothing twice.
    await tester.pumpWidget(const SizedBox());
  });
}
