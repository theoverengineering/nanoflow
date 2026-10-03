import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/graph/canvas/copies_frame.dart';
import 'package:nanoflow_ui/graph/canvas/frame_toggle.dart';
import 'package:nanoflow_ui/graph/canvas/function_frame.dart';
import 'package:nanoflow_ui/graph/canvas/graph_canvas.dart';
import 'package:nanoflow_ui/graph/canvas/node_tile.dart';
import 'package:nanoflow_ui/graph/copy_switcher.dart';
import 'package:nanoflow_ui/graph/logs/logs_panel.dart';
import 'package:nanoflow_ui/graph/logs/step_list.dart';
import 'package:nanoflow_ui/state/body_path.dart';
import 'package:nanoflow_ui/state/graph_model.dart';

import '../../support/golden.dart';
import '../logs/support.dart';
import '../support.dart';
import 'support.dart';

void main() {
  final controller = GraphCanvasController();

  /// The canvas of [model]; a `+` expands as its node alone opens.
  Future<void> pumpCanvas(WidgetTester tester, GraphModel model) async {
    await pumpScreen(
      tester,
      GraphCanvas(
        model: model,
        controller: controller,
        onExpandNode: (path, node, _) => model.expandNode(
          path,
          openings(node, model.canvas.file!.functions).first,
        ),
      ),
      size: reviewCanvas,
    );
    await settle(tester);
  }

  Finder node(String id) => find.byKey(NodeTile.keyOf(id));
  Finder tile(String id) => find.byKey(NodeTile.tileKeyOf(id));
  Finder expand(String id) => find.byKey(FrameToggle.expandKeyOf(id));
  Finder collapse(String id) => find.byKey(FrameToggle.collapseKeyOf(id));

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
    await settle(tester);
  }

  /// The canvas on screen, under the room kept for the session bar.
  Rect viewport(WidgetTester tester) {
    final canvas = tester.getRect(find.byType(GraphCanvas));
    return Rect.fromLTRB(
      canvas.left,
      canvas.top + GraphCanvas.sessionBarRoom,
      canvas.right,
      canvas.bottom,
    );
  }

  bool inside(Rect outer, Rect inner) =>
      inner.left >= outer.left - 0.01 &&
      inner.top >= outer.top - 0.01 &&
      inner.right <= outer.right + 0.01 &&
      inner.bottom <= outer.bottom + 0.01;

  testWidgets('+ on a call draws its function in place: the frame titled '
      'publish(), its nodes; − gives the tile back', (tester) async {
    final model = modelOf();
    await pumpCanvas(tester, model);
    expect(expand('5'), findsOneWidget);
    expect(expand('1'), findsNothing, reason: 'a step does not expand');

    await tap(tester, expand('5'));
    expect(node('5'), findsNothing);
    expect(find.byType(FunctionFrameView), findsOneWidget);
    expect(find.text('publish()'), findsOneWidget);
    for (final id in ['5/1', '5/2', '5/3', '5/4']) {
      expect(tile(id), findsOneWidget, reason: id);
    }
    expect(find.text('upload'), findsOneWidget);
    // The function's nodes are in the frame, under its title.
    final frame = tester.getRect(find.byType(FunctionFrameView));
    final title = tester.getRect(find.text('publish()'));
    for (final id in ['5/1', '5/4']) {
      final rect = tester.getRect(tile(id));
      expect(inside(frame, rect), isTrue, reason: id);
      expect(rect.top, greaterThan(title.bottom), reason: id);
    }

    await tap(tester, collapse('5'));
    expect(find.byType(FunctionFrameView), findsNothing);
    expect(tile('5'), findsOneWidget);
    expect(tile('5/1'), findsNothing);
  });

  testWidgets('a frame in a frame: copies, and the call in them, at any '
      'depth the same', (tester) async {
    final model = modelOf(
      graph: GraphFile.fromJson({
        ...graphFileNamed('inline').toJson(),
        'workflows': ['lib/inline.dart#viaCall'],
      }),
    );
    await pumpCanvas(tester, model);
    await tap(tester, expand('1'));
    expect(find.text('each pkg in packages'), findsOneWidget);
    expect(find.text('×n · in parallel'), findsOneWidget);
    expect(find.byType(CopySwitcher), findsNothing, reason: 'no session');

    await tap(tester, expand('1/1'));
    expect(find.byType(FunctionFrameView), findsOneWidget);
    for (final id in ['1/1/1', '1/1/2', '1/1/3']) {
      expect(tile(id), findsOneWidget, reason: id);
    }
    final copies = tester.getRect(find.byType(CopiesFrameView));
    final call = tester.getRect(find.byType(FunctionFrameView));
    expect(inside(copies, call), isTrue);

    // Collapsing the copies forgets what was expanded in them.
    await tap(tester, collapse('1'));
    await tap(tester, expand('1'));
    expect(find.byType(FunctionFrameView), findsNothing);
  });

  testWidgets('a node expanded stays where it was on the screen once the '
      'view is moved; while the view is fitted, it fits again', (tester) async {
    final model = modelOf();
    await pumpCanvas(tester, model);
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.drag(find.byType(GraphCanvas), const Offset(-600, -100));
    await tester.pump();
    final at = tester.getTopLeft(tile('5'));

    await tap(tester, expand('5'));
    expect(
      tester.getTopLeft(find.byType(FunctionFrameView)),
      offsetMoreOrLessEquals(at),
    );
    expect(inside(viewport(tester), tester.getRect(collapse('5'))), isTrue);
    await tap(tester, collapse('5'));
    expect(tester.getTopLeft(tile('5')), offsetMoreOrLessEquals(at));

    await tap(tester, find.byTooltip('Zoom to fit'));
    await tap(tester, expand('5'));
    for (final id in ['1', '8', '5/1', '5/4']) {
      expect(
        inside(viewport(tester), tester.getRect(tile(id))),
        isTrue,
        reason: id,
      );
    }
  });

  testWidgets('a node in a frame is revealed by its path', (tester) async {
    final model = modelOf();
    await pumpCanvas(tester, model);
    await tap(tester, expand('5'));
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip('Zoom in'));
    }
    await tester.pump();
    expect(inside(viewport(tester), tester.getRect(tile('5/4'))), isFalse);

    controller.revealNode('5/4');
    await tester.pump();
    expect(inside(viewport(tester), tester.getRect(tile('5/4'))), isTrue);
  });

  group('on the graph screen', () {
    testWidgets('+ on a call of an interface method offers its '
        'implementations; the one chosen is drawn in place', (tester) async {
      final model = await pumpGraphScreen(
        tester,
        model: ownedModel(
          file: releaseFile,
          graph: graphFileNamed('interfaces'),
        ),
      );
      await tap(tester, expand('2'));
      await tester.tap(find.text('MailNotifier.notify()').last);
      await tester.pumpAndSettle();
      expect(find.text('MailNotifier.notify()'), findsOneWidget);
      expect(find.byType(FunctionFrameView), findsOneWidget);
      expect(model.canvas.frames.single.path, const [
        Opened('2', functionId: 'lib/deploy.dart#MailNotifier.notify'),
      ]);
    });

    testWidgets('a double click on a node in a frame opens it from there', (
      tester,
    ) async {
      final model = await pumpGraphScreen(
        tester,
        path: inlineFile,
        model: ownedModel(
          file: inlineFile,
          graph: GraphFile.fromJson({
            ...graphFileNamed('inline').toJson(),
            'workflows': ['lib/inline.dart#viaCall'],
          }),
        ),
      );
      await tap(tester, expand('1'));
      await tester.tap(tile('1/1'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(tile('1/1'));
      await settle(tester);
      expect(
        [for (final level in model.canvas.levels) level.title],
        ['viaCall', 'pkg in packages', 'publish()'],
      );
    });

    testWidgets('copies in place with a session: the stack, what they are '
        'over, the switcher, how they stand; a copy chosen there is shown, '
        'and Logs follow it', (tester) async {
      final model = await pumpGraphScreen(
        tester,
        path: inlineFile,
        model: copiesModel(),
        now: () => columnNow,
      );
      await tap(tester, expand('1'));
      expect(find.text('each pkg in packages'), findsOneWidget);
      expect(find.text('×3 · in parallel'), findsOneWidget);
      expect(textIn(tester, find.byType(CopySwitcher)), 'all 1 2 3');
      expect(
        textIn(tester, find.byKey(CopiesFrameView.footerKey)),
        'done 1 of 3',
      );
      // How many copies are on each step now.
      expect(find.byKey(NodeTile.runningKeyOf('1/2')), findsOneWidget);
      expect(find.byKey(NodeTile.runningKeyOf('1/3')), findsOneWidget);

      await tap(tester, find.byKey(CopySwitcher.chipKey(2)));
      expect(
        textIn(tester, find.byKey(CopiesFrameView.footerKey)),
        'pkg 2 · now verify',
      );
      expect(
        textIn(tester, find.byKey(LogsPanel.titleKey)),
        'Logs pkg 2 · 2 steps',
      );
      expect(model.selection.stepId, 'c0c0-verify-4');
      final tag = tester.widget<NodeTile>(node('1/3'));
      expect(tag.marks!.steps, 0, reason: 'tool has not reached tag');

      // Opened, the copies show the same copy.
      model.open(const Opened('1'));
      await settle(tester);
      expect(
        textIn(tester, find.byKey(CopiesFrameView.footerKey)),
        'pkg 2 · now verify',
      );
    });

    testWidgets('a step of Logs in a frame is shown at its node in the frame', (
      tester,
    ) async {
      await pumpGraphScreen(
        tester,
        path: inlineFile,
        model: copiesModel(),
        now: () => columnNow,
      );
      await tap(tester, expand('1'));
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip('Zoom in'));
      }
      await tester.pump();
      final canvas = tester.getRect(find.byType(GraphCanvas));
      expect(
        canvas.intersect(tester.getRect(tile('1/1'))),
        isNot(tester.getRect(tile('1/1'))),
      );

      await tap(tester, find.byKey(StepList.rowKey('c0c0-upload-0')));
      expect(
        inside(canvas, tester.getRect(tile('1/1'))),
        isTrue,
        reason: 'upload is revealed in the frame',
      );
    });
  });
}
