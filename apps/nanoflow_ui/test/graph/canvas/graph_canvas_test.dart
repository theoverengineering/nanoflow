import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart' hide Route;
import 'package:nanoflow_ui/graph/canvas/exit_labels.dart';
import 'package:nanoflow_ui/graph/canvas/graph_canvas.dart';
import 'package:nanoflow_ui/graph/canvas/legend.dart';
import 'package:nanoflow_ui/graph/canvas/node_tile.dart';
import 'package:nanoflow_ui/state/graph_marks.dart';
import 'package:nanoflow_ui/state/graph_model.dart';

import '../../state/support.dart';
import '../../support/golden.dart';
import 'support.dart';

void main() {
  final controller = GraphCanvasController();

  Future<void> pumpCanvas(
    WidgetTester tester,
    GraphModel model, {
    ValueChanged<String>? onOpenStep,
    Size size = reviewCanvas,
  }) async {
    await pumpScreen(
      tester,
      GraphCanvas(
        model: model,
        now: () => Mockup.now,
        controller: controller,
        onOpenStep: onOpenStep,
      ),
      size: size,
    );
    await settle(tester);
  }

  Finder tile(String node) => find.byKey(NodeTile.tileKeyOf(node));

  NodeTile nodeTile(WidgetTester tester, String node) =>
      tester.widget<NodeTile>(find.byKey(NodeTile.keyOf(node)));

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

  group('a click on a node', () {
    testWidgets('selects its last step in the selected run', (tester) async {
      final model = reviewModel();
      await pumpCanvas(tester, model);
      expect(model.selection.runId, 'e5f6-run');
      expect(model.selection.stepId, 'e5f6-notify-0');

      await tester.tap(tile('inspect'));
      await tester.pump(const Duration(milliseconds: 500));

      // The run's second inspect step, inherited from k7f2.
      expect(model.selection.stepId, 'k7f2-inspect-5');
      expect(model.selection.following, isFalse);
    });

    testWidgets('does nothing when the selected run has no step on the node', (
      tester,
    ) async {
      final model = reviewModel();
      await pumpCanvas(tester, model);

      // Never visited; and visited, but by c3d4, not by the selected e5f6.
      for (final node in ['discard', 'publish']) {
        await tester.tap(tile(node));
        await tester.pump(const Duration(milliseconds: 500));
        expect(model.selection.stepId, 'e5f6-notify-0');
      }
    });

    testWidgets('a double click opens the step details', (tester) async {
      final model = reviewModel();
      final opened = <String>[];
      await pumpCanvas(tester, model, onOpenStep: opened.add);

      await tester.tap(tile('verdict'));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(tile('verdict'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(opened, ['verdict']);
      expect(model.selection.stepId, 'k7f2-verdict-6');

      // Two clicks far apart in time are two clicks.
      await tester.tap(tile('fix'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(tile('fix'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(opened, ['verdict']);
    });

    testWidgets('a double click opens a node without steps too', (
      tester,
    ) async {
      final model = reviewModel();
      final opened = <String>[];
      await pumpCanvas(tester, model, onOpenStep: opened.add);

      await tester.tap(tile('discard'));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(tile('discard'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(opened, ['discard']);
    });
  });

  testWidgets('the pointer over a node is a hand', (tester) async {
    await pumpCanvas(tester, reviewModel());
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);

    await mouse.addPointer(location: tester.getCenter(tile('collect')));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );

    final empty = tester.getRect(find.byType(GraphCanvas)).topLeft;
    await mouse.moveTo(empty + const Offset(300, 70));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      isNot(SystemMouseCursors.click),
    );
  });

  group('the view', () {
    testWidgets('fits the graph under the session bar when first shown', (
      tester,
    ) async {
      await pumpCanvas(tester, taskModel(), size: taskCanvas);

      // The task graph is wider than the canvas: it is made smaller.
      expect(controller.scale, lessThan(1));
      for (final node in ['admit', 'accept', 'human-answer']) {
        expect(inside(viewport(tester), tester.getRect(tile(node))), isTrue);
      }
    });

    testWidgets('fits again when the canvas is resized, until the view is '
        'moved', (tester) async {
      await pumpCanvas(tester, taskModel(), size: taskCanvas);
      final fitted = controller.scale;

      tester.view.physicalSize = const Size(2400, 672) * 2;
      await tester.pump();
      expect(controller.scale, greaterThan(fitted));

      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pump();
      final zoomed = controller.scale;
      tester.view.physicalSize = taskCanvas * 2;
      await tester.pump();
      expect(controller.scale, zoomed);
    });

    testWidgets('does not make a small graph bigger than drawn', (
      tester,
    ) async {
      await pumpCanvas(tester, reviewModel(), size: const Size(1800, 900));
      expect(controller.scale, 1);
    });

    testWidgets('+ and − zoom, the fit button fits again', (tester) async {
      await pumpCanvas(tester, reviewModel());
      final fitted = controller.scale;

      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      expect(controller.scale, greaterThan(fitted));
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      expect(inside(viewport(tester), tester.getRect(tile('fix'))), isFalse);

      await tester.tap(find.byTooltip('Zoom out'));
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pump();
      expect(controller.scale, lessThan(fitted));

      await tester.tap(find.byTooltip('Zoom to fit'));
      await tester.pump();
      expect(controller.scale, fitted);
      for (final node in ['collect', 'publish', 'fix']) {
        expect(inside(viewport(tester), tester.getRect(tile(node))), isTrue);
      }
    });

    testWidgets('a drag pans', (tester) async {
      await pumpCanvas(tester, reviewModel());
      final before = tester.getRect(tile('collect'));

      final empty = tester.getRect(find.byType(GraphCanvas)).topLeft;
      await tester.dragFrom(
        empty + const Offset(300, 80),
        const Offset(-120, 40),
      );
      await tester.pump();

      final after = tester.getRect(tile('collect'));
      expect(after.topLeft - before.topLeft, const Offset(-120, 40));
    });

    testWidgets('a two-finger trackpad swipe pans, a pinch zooms', (
      tester,
    ) async {
      await pumpCanvas(tester, reviewModel());
      final scale = controller.scale;
      final before = tester.getRect(tile('collect'));
      final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
      final at = tester.getCenter(find.byType(GraphCanvas));

      await tester.sendEventToBinding(trackpad.panZoomStart(at));
      await tester.sendEventToBinding(
        trackpad.panZoomUpdate(at, pan: const Offset(-60, 30)),
      );
      await tester.sendEventToBinding(trackpad.panZoomEnd());
      await tester.pump();
      expect(controller.scale, scale);
      final moved = tester.getRect(tile('collect')).topLeft - before.topLeft;
      expect(moved.dx, lessThan(-50));
      expect(moved.dy, greaterThan(20));

      await tester.sendEventToBinding(trackpad.panZoomStart(at));
      await tester.sendEventToBinding(trackpad.panZoomUpdate(at, scale: 1.5));
      await tester.sendEventToBinding(trackpad.panZoomEnd());
      await tester.pump();
      expect(controller.scale, greaterThan(scale));
    });

    testWidgets('the scroll wheel pans; with ⌘ or Ctrl it zooms', (
      tester,
    ) async {
      await pumpCanvas(tester, reviewModel());
      final scale = controller.scale;
      final before = tester.getRect(tile('collect'));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      final at = tester.getCenter(find.byType(GraphCanvas));

      await tester.sendEventToBinding(pointer.hover(at));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 50)));
      await tester.pump();
      expect(controller.scale, scale);
      expect(
        tester.getRect(tile('collect')).topLeft - before.topLeft,
        const Offset(0, -50),
      );

      for (final key in [
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.controlLeft,
      ]) {
        final zoom = controller.scale;
        await tester.sendKeyDownEvent(key);
        await tester.sendEventToBinding(pointer.scroll(const Offset(0, -50)));
        await tester.sendKeyUpEvent(key);
        await tester.pump();
        expect(controller.scale, greaterThan(zoom));
      }
    });

    testWidgets('revealNode brings a node out of view into it, and leaves a '
        'node in view where it is', (tester) async {
      await pumpCanvas(tester, reviewModel());
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Zoom in'));
      }
      await tester.pump();
      expect(inside(viewport(tester), tester.getRect(tile('fix'))), isFalse);

      controller.revealNode('fix');
      await tester.pump();
      expect(inside(viewport(tester), tester.getRect(tile('fix'))), isTrue);

      final offset = controller.offset;
      controller.revealNode('fix');
      await tester.pump();
      expect(controller.offset, offset);
    });

    testWidgets('keeps the view on live updates and fits a graph of another '
        'shape', (tester) async {
      final model = reviewModel(
        current: Graph.fromJson(const {
          'start': 'only',
          'nodes': {
            'only': {'command': 'only.sh'},
          },
        }),
      );
      await pumpCanvas(tester, model);
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      final zoomed = controller.scale;

      // Another run of the session: the same graph.
      model.selectRun('c3d4-run');
      await settle(tester);
      expect(controller.scale, zoomed);

      // Current graph: another graph, made of one node.
      model.selection.showCurrentGraph();
      await settle(tester);
      expect(controller.scale, 1);
    });
  });

  group('Current graph', () {
    testWidgets('has no states, counters or run markers', (tester) async {
      final model = reviewModel(current: Graph.fromJson(reviewGraph));
      await pumpCanvas(tester, model);
      expect(find.text('e5f6'), findsOneWidget);
      expect(find.text('2×'), findsNWidgets(2));
      expect(_chips(tester), contains('2×'));

      model.selection.showCurrentGraph();
      await settle(tester);

      expect(find.text('e5f6'), findsNothing);
      expect(find.text('c3d4'), findsNothing);
      expect(find.text('2×'), findsNothing);
      expect(_chips(tester).where((text) => text.endsWith('×')), isEmpty);
      for (final node in tester.widgetList<NodeTile>(find.byType(NodeTile))) {
        expect(node.state, isNull);
        expect(node.selected, isFalse);
      }
      expect(find.text('taken by run e5f6'), findsNothing);
      expect(find.text('back edge'), findsOneWidget);
    });

    testWidgets('says No valid graph yet until a graph passes check', (
      tester,
    ) async {
      await pumpCanvas(tester, modelOf());
      expect(find.text('No valid graph yet'), findsOneWidget);
      expect(find.byType(NodeTile), findsNothing);
    });
  });

  testWidgets('says when the selected session\'s graph cannot be read', (
    tester,
  ) async {
    final run = Journal('bad1-run', node: 'collect', startedAt: 0);
    await pumpCanvas(
      tester,
      modelOf(changes: changesOf([run], graph: const {'start': 'collect'})),
    );
    expect(find.text('Graph of this session cannot be read'), findsOneWidget);
  });

  group('the legend', () {
    testWidgets('names the selected run and the kinds of arrows the graph '
        'has', (tester) async {
      await pumpCanvas(tester, reviewModel());
      expect(find.byType(Legend), findsOneWidget);
      expect(find.text('taken by run e5f6'), findsOneWidget);
      expect(find.text('back edge'), findsOneWidget);
      // The review graph has no empty targets.
      expect(find.text('outcome with no target — run ends'), findsNothing);
    });

    testWidgets('of the task graph tells of outcomes without a target', (
      tester,
    ) async {
      await pumpCanvas(tester, taskModel(), size: taskCanvas);
      expect(find.text('taken by run t9m4'), findsOneWidget);
      expect(find.text('outcome with no target — run ends'), findsOneWidget);
    });
  });

  testWidgets('the sign of a running node turns', (tester) async {
    await pumpCanvas(tester, reviewModel());
    Animation<double> turns(String node) => tester
        .widget<RotationTransition>(
          find.descendant(
            of: find.byKey(NodeTile.keyOf(node)),
            matching: find.byType(RotationTransition),
          ),
        )
        .turns;

    final before = turns('notify').value;
    await tester.pump(const Duration(milliseconds: 300));
    expect(turns('notify').value, isNot(before));
    // Only a running node has the sign.
    expect(
      find.descendant(
        of: find.byKey(NodeTile.keyOf('fix')),
        matching: find.byType(RotationTransition),
      ),
      findsNothing,
    );
  });

  testWidgets('the selected step\'s node is ringed and its run marked', (
    tester,
  ) async {
    await pumpCanvas(tester, reviewModel());
    final notify = nodeTile(tester, 'notify');
    expect(notify.selected, isTrue);
    expect(notify.state, NodeState.running);
    expect([for (final m in notify.markers) m.shortId], ['e5f6']);
    final inspect = nodeTile(tester, 'inspect');
    expect(inspect.selected, isFalse);
    expect(inspect.visits, '2×');
    expect(nodeTile(tester, 'discard').state, NodeState.notVisited);
  });
}

/// The texts of the chips on the canvas: exit keys and counters.
List<String> _chips(WidgetTester tester) => [
  for (final paint in tester.widgetList<CustomPaint>(find.byType(CustomPaint)))
    if (paint.painter case final ExitsPainter exits)
      for (final chip in exits.chips) chip.text,
];
