import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart' hide Route;
import 'package:nanoflow_ui/graph/canvas/graph_canvas.dart';
import 'package:nanoflow_ui/graph/canvas/node_tile.dart';
import 'package:nanoflow_ui/graph/graph_notes.dart';
import 'package:nanoflow_ui/graph/graph_screen.dart';
import 'package:nanoflow_ui/graph/header.dart';
import 'package:nanoflow_ui/graph/session_bar.dart';
import 'package:nanoflow_ui/graph/sessions_column.dart';
import 'package:nanoflow_ui/platform/shell.dart';

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

  testWidgets('lays out the header, the sessions column and the canvas', (
    tester,
  ) async {
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
      const Rect.fromLTRB(272, 48, 1440, 900),
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
      const Rect.fromLTRB(332, 48, 1440, 900),
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

    testWidgets('on a step opens nothing', (tester) async {
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
        openModel: (file) {
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

  testWidgets('disposes its model when the app is quit', (tester) async {
    final model = await pumpGraphScreen(tester);

    await tester.binding.handleRequestAppExit();
    expect(graphFileOf(model).disposed, isTrue);

    // Leaving after that disposes nothing twice.
    await tester.pumpWidget(const SizedBox());
  });
}
