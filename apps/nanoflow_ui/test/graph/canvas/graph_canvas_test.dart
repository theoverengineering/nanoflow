import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/graph/canvas/canvas_marks.dart';
import 'package:nanoflow_ui/graph/canvas/canvas_style.dart';
import 'package:nanoflow_ui/graph/canvas/edges_painter.dart';
import 'package:nanoflow_ui/graph/canvas/exit_labels.dart';
import 'package:nanoflow_ui/graph/canvas/graph_canvas.dart';
import 'package:nanoflow_ui/graph/canvas/layout_geometry.dart';
import 'package:nanoflow_ui/graph/canvas/legend.dart';
import 'package:nanoflow_ui/graph/canvas/node_tile.dart';
import 'package:nanoflow_ui/graph/canvas/tile_marks.dart';
import 'package:nanoflow_ui/layout/layout.dart' show endMarker, startMarker;
import 'package:nanoflow_ui/state/body_path.dart';
import 'package:nanoflow_ui/state/graph_marks.dart' show NodeState;
import 'package:nanoflow_ui/state/graph_model.dart';

import '../../state/support.dart';
import '../../support/golden.dart';
import 'support.dart';

void main() {
  final controller = GraphCanvasController();

  /// The review example's graph file, its workflow drawn.
  GraphFile review() => graphFileNamed('review');

  /// The task mockup's graph: wider than any canvas.
  GraphFile task() => graphFileNamed('task');

  Future<void> pumpCanvas(
    WidgetTester tester,
    GraphModel model, {
    OpenNode? onOpenNode,
    Size size = reviewCanvas,
  }) async {
    await pumpScreen(
      tester,
      GraphCanvas(model: model, controller: controller, onOpenNode: onOpenNode),
      size: size,
    );
    await settle(tester);
  }

  Finder tile(String id) => find.byKey(NodeTile.tileKeyOf(id));

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

  Future<void> doubleTap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('the graph', () {
    testWidgets('is one level: the workflow\'s body between its markers, a '
        'tile for each node', (tester) async {
      await pumpCanvas(tester, modelOf(graph: review()));
      final tiles = tester.widgetList<NodeTile>(find.byType(NodeTile));
      expect(
        [for (final t in tiles) t.node.id],
        [
          startMarker,
          for (var i = 1; i <= 8; i++) '$i',
          endMarker,
          '${endMarker}2',
          '${endMarker}3',
        ],
      );
      expect(find.text('start'), findsOneWidget);
      expect(find.text('end'), findsNWidgets(3));
      expect(find.text('collect'), findsOneWidget);
      expect(find.text('review.dart:49'), findsOneWidget);
      expect(find.text('change.path.isEmpty'), findsOneWidget);
      expect(_chips(tester), containsAll(['true', 'false']));
    });

    testWidgets('draws a call as a stack with its effects counted, copies as '
        'one with the effects of a copy and ×n', (tester) async {
      await pumpCanvas(tester, modelOf());
      expect(find.text('publish()'), findsOneWidget);
      expect(find.text('{ 3 }'), findsOneWidget);
      expect(_chips(tester), containsAll(['each', 'done', 'Channel.dev']));

      await pumpCanvas(
        tester,
        modelOf(
          graph: GraphFile.fromJson({
            ...graphFileNamed('inline').toJson(),
            'workflows': ['lib/inline.dart#inPlace'],
          }),
        ),
      );
      expect(find.text('pkg in packages'), findsOneWidget);
      expect(find.text('{ 3 }'), findsOneWidget);
      expect(find.text('×n'), findsOneWidget);
    });

    testWidgets('a double click on a call or copies opens it, on another '
        'node does nothing', (tester) async {
      final opened = <(String, Offset)>[];
      await pumpCanvas(
        tester,
        modelOf(),
        onOpenNode: (_, node, at) => opened.add((node.id, at)),
      );

      await doubleTap(tester, tile('5'));
      expect([for (final (id, _) in opened) id], ['5']);
      expect(opened.single.$2, tester.getCenter(tile('5')));

      await doubleTap(tester, tile('3'));
      await doubleTap(tester, tile(startMarker));
      expect(opened, hasLength(1));

      // Two clicks far apart in time are two clicks.
      await tester.tap(tile('5'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(tile('5'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(opened, hasLength(1));
    });

    testWidgets('the pointer over a node that opens is a hand', (tester) async {
      await pumpCanvas(tester, modelOf(), onOpenNode: (_, _, _) {});
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      MouseCursor cursor() =>
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1)!;

      await mouse.addPointer(location: tester.getCenter(tile('5')));
      await tester.pump();
      expect(cursor(), SystemMouseCursors.click);

      await mouse.moveTo(tester.getCenter(tile('3')));
      await tester.pump();
      expect(cursor(), isNot(SystemMouseCursors.click));
    });

    testWidgets('draws what the model opens', (tester) async {
      final model = modelOf();
      await pumpCanvas(tester, model);
      model.open(_publish(model.canvas.body!.node('5')!));
      await settle(tester);
      expect(find.text('upload'), findsOneWidget);
      expect(find.text('publish()'), findsNothing);
    });
  });

  group('the view', () {
    testWidgets('fits the graph under the session bar when first shown', (
      tester,
    ) async {
      await pumpCanvas(tester, modelOf(graph: task()));

      // The task graph is wider than the canvas: it is made smaller.
      expect(controller.scale, lessThan(1));
      for (final node in ['admit', 'accept', 'human-answer']) {
        expect(inside(viewport(tester), tester.getRect(tile(node))), isTrue);
      }
    });

    testWidgets('fits again when the canvas is resized, until the view is '
        'moved', (tester) async {
      await pumpCanvas(tester, modelOf(graph: task()));
      final fitted = controller.scale;

      tester.view.physicalSize = const Size(2400, 672) * 2;
      await tester.pump();
      expect(controller.scale, greaterThan(fitted));

      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pump();
      final zoomed = controller.scale;
      tester.view.physicalSize = reviewCanvas * 2;
      await tester.pump();
      expect(controller.scale, zoomed);
    });

    testWidgets('fits again under a new top inset, until the view is moved', (
      tester,
    ) async {
      final model = modelOf(graph: review());
      Future<void> pumpInset(double inset) async {
        await pumpScreen(
          tester,
          GraphCanvas(model: model, controller: controller, topInset: inset),
          size: reviewCanvas,
        );
        await settle(tester);
      }

      await pumpInset(GraphCanvas.sessionBarRoom);
      final canvas = tester.getRect(find.byType(GraphCanvas));
      await pumpInset(200);
      expect(
        tester.getRect(tile('3')).top,
        greaterThanOrEqualTo(canvas.top + 200),
      );

      // No more than half the canvas is kept free.
      await pumpInset(5000);
      expect(
        tester.getRect(tile('3')).top,
        moreOrLessEquals(canvas.top + canvas.height / 2, epsilon: 20),
      );
      expect(tester.getRect(tile('8')).bottom, lessThan(canvas.bottom));

      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pump();
      final view = (controller.scale, controller.offset);
      await pumpInset(GraphCanvas.sessionBarRoom);
      expect((controller.scale, controller.offset), view);
    });

    testWidgets('does not make a small graph bigger than drawn', (
      tester,
    ) async {
      await pumpCanvas(
        tester,
        modelOf(graph: review()),
        size: const Size(1800, 900),
      );
      expect(controller.scale, 1);
    });

    testWidgets('+ and − zoom, the fit button fits again', (tester) async {
      await pumpCanvas(tester, modelOf(graph: review()));
      final fitted = controller.scale;

      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      expect(controller.scale, greaterThan(fitted));
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      expect(inside(viewport(tester), tester.getRect(tile('8'))), isFalse);

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip('Zoom out'));
      }
      await tester.pump();
      expect(controller.scale, lessThan(fitted));

      await tester.tap(find.byTooltip('Zoom to fit'));
      await tester.pump();
      expect(controller.scale, fitted);
      for (final node in ['1', '6', '8']) {
        expect(inside(viewport(tester), tester.getRect(tile(node))), isTrue);
      }
    });

    testWidgets('a drag pans', (tester) async {
      await pumpCanvas(tester, modelOf(graph: review()));
      final before = tester.getRect(tile('1'));

      final empty = tester.getRect(find.byType(GraphCanvas)).topLeft;
      await tester.dragFrom(
        empty + const Offset(300, 80),
        const Offset(-120, 40),
      );
      await tester.pump();

      final after = tester.getRect(tile('1'));
      expect(after.topLeft - before.topLeft, const Offset(-120, 40));
    });

    testWidgets('a two-finger trackpad swipe pans, a pinch zooms', (
      tester,
    ) async {
      await pumpCanvas(tester, modelOf(graph: review()));
      final scale = controller.scale;
      final before = tester.getRect(tile('1'));
      final trackpad = TestPointer(1, PointerDeviceKind.trackpad);
      final at = tester.getCenter(find.byType(GraphCanvas));

      await tester.sendEventToBinding(trackpad.panZoomStart(at));
      await tester.sendEventToBinding(
        trackpad.panZoomUpdate(at, pan: const Offset(-60, 30)),
      );
      await tester.sendEventToBinding(trackpad.panZoomEnd());
      await tester.pump();
      expect(controller.scale, scale);
      final moved = tester.getRect(tile('1')).topLeft - before.topLeft;
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
      await pumpCanvas(tester, modelOf(graph: review()));
      final scale = controller.scale;
      final before = tester.getRect(tile('1'));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      final at = tester.getCenter(find.byType(GraphCanvas));

      await tester.sendEventToBinding(pointer.hover(at));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 50)));
      await tester.pump();
      expect(controller.scale, scale);
      expect(
        tester.getRect(tile('1')).topLeft - before.topLeft,
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
      await pumpCanvas(tester, modelOf(graph: review()));
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Zoom in'));
      }
      await tester.pump();
      expect(inside(viewport(tester), tester.getRect(tile('8'))), isFalse);

      controller.revealNode('8');
      await tester.pump();
      expect(inside(viewport(tester), tester.getRect(tile('8'))), isTrue);

      final offset = controller.offset;
      controller.revealNode('8');
      await tester.pump();
      expect(controller.offset, offset);
    });

    testWidgets('keeps the view when the graph file is written again the '
        'same, and fits a level drawn otherwise', (tester) async {
      final model = modelOf(graph: review());
      await pumpCanvas(tester, model);
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      final (scale, offset) = (controller.scale, controller.offset);

      // describe wrote the file again, with a new fingerprint.
      graphFileOf(model).graph = GraphFile.fromJson({
        ...review().toJson(),
        'fingerprint': 'sha256:other',
      });
      await settle(tester);
      expect(controller.scale, scale);
      expect(controller.offset, offset);

      graphFileOf(model).graph = graphFileNamed('release');
      await settle(tester);
      expect(controller.scale, isNot(scale));
      expect(find.text('publish()'), findsOneWidget);
    });

    testWidgets('keeps the view as sessions come', (tester) async {
      final more = StreamController<Change>();
      addTearDown(more.close);
      final model = modelOf(graph: review(), more: more.stream);
      await pumpCanvas(tester, model);
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      final (scale, offset) = (controller.scale, controller.offset);

      final session = Journal('a1b2-session', graph: review().toJson())
        ..effect('collect', 1);
      session.changes.forEach(more.add);
      await settle(tester);
      expect(model.selection.sessionId, 'a1b2-session');
      expect(controller.scale, scale);
      expect(controller.offset, offset);
    });
  });

  group('Current graph', () {
    testWidgets('has no legend: only the zoom buttons', (tester) async {
      await pumpCanvas(tester, modelOf(graph: review()));
      // ui-spec «Холст»: for Current graph only the zoom buttons remain.
      expect(find.byType(Legend), findsNothing);
      expect(find.byTooltip('Zoom to fit'), findsOneWidget);
    });

    testWidgets('says No valid graph yet until a graph file is read', (
      tester,
    ) async {
      await pumpCanvas(tester, modelOf(noGraph: true));
      expect(find.text('No valid graph yet'), findsOneWidget);
      expect(find.byType(NodeTile), findsNothing);
    });

    testWidgets('draws nothing once the graph drawn has gone', (tester) async {
      final model = modelOf();
      await pumpCanvas(tester, model);
      expect(find.byType(NodeTile), findsWidgets);
      graphFileOf(model).graph = GraphFile.fromJson({
        ...graphFileNamed('release').toJson(),
        'workflows': <String>[],
      });
      await settle(tester);
      expect(find.text('The graph file has no workflows'), findsOneWidget);
      expect(find.byType(NodeTile), findsNothing);
    });
  });

  testWidgets('a session\'s graph names its back arrows in the legend', (
    tester,
  ) async {
    await pumpCanvas(
      tester,
      modelOf(
        graph: review(),
        changes: changesOf([Journal('a1b2-session', graph: review().toJson())]),
      ),
    );
    expect(find.byType(Legend), findsOneWidget);
    expect(find.text('back edge'), findsOneWidget);
    expect(tester.widget<Legend>(find.byType(Legend)).backEdges, Tone.plain);
  });

  group('the selected effect\'s node', () {
    /// A session of the release fixture whose `plan` runs: its node, `1`,
    /// is the selected effect's.
    GraphModel planRunning() {
      final release = graphFileNamed('release');
      final j = Journal(
        'r1r1-session',
        workflow: 'release',
        graph: release.toJson(),
      )..effect('plan', 1, place: 'lib/release.dart:16');
      return modelOf(graph: release, changes: j.changes);
    }

    testWidgets('has its ring under the arrows and exits: the bar of its '
        'input and the half of its exit dot stay over the ring', (
      tester,
    ) async {
      await pumpCanvas(tester, planRunning());
      final ring = find.byKey(NodeTile.ringKeyOf('1'));
      expect(ring, findsOneWidget);
      final layers = tester.widget<Stack>(
        find.ancestor(of: ring, matching: find.byType(Stack)).first,
      );
      int indexOf(bool Function(Widget child) test) =>
          layers.children.indexWhere(test);
      bool paints<T>(Widget child) =>
          child is Positioned &&
          child.child is CustomPaint &&
          (child.child as CustomPaint).painter is T;
      final rings = indexOf((child) => child.key == NodeTile.ringKeyOf('1'));
      expect(rings, lessThan(indexOf(paints<EdgesPainter>)));
      expect(rings, lessThan(indexOf(paints<ExitsPainter>)));
      // Round the tile, as far out on every side.
      final round = tester.getRect(ring);
      final inner = tester.getRect(tile('1'));
      expect(round.center.dx, closeTo(inner.center.dx, 0.01));
      expect(round.center.dy, closeTo(inner.center.dy, 0.01));
      expect(round.width - inner.width, greaterThan(0));
      expect(
        round.width - inner.width,
        closeTo(round.height - inner.height, 0.01),
      );
    });

    testWidgets('keeps its tile and its name as they are: no ring on the '
        'tile itself, no bolder name', (tester) async {
      await pumpCanvas(tester, planRunning());
      final box =
          tester.widget<DecoratedBox>(tile('1')).decoration as BoxDecoration;
      expect(box.boxShadow ?? const [], isEmpty);
      expect(
        tester.widget<Text>(find.text('plan')).style!.fontWeight,
        TileLook.of(NodeState.running).nameWeight,
      );
    });

    testWidgets('has its input bar outlined in the canvas\'s colour, as its '
        'exit dot is: the bar stands out of the ring round it', (tester) async {
      await pumpCanvas(tester, planRunning());
      final paint = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .firstWhere((paint) => paint.painter is EdgesPainter);
      final bar = (paint.painter! as EdgesPainter).graph.nodes['1']!.bar!.rect
          .toRect();
      expect(
        tester.renderObject(find.byWidget(paint)),
        paints
          ..rrect(
            rrect: RRect.fromRectAndRadius(
              bar.inflate(1),
              const Radius.circular(3),
            ),
            color: CanvasColors.background,
          )
          ..rrect(
            rrect: RRect.fromRectAndRadius(bar, const Radius.circular(2)),
            color: CanvasColors.plain,
          ),
      );
    });
  });

  testWidgets('says when the selected session\'s graph cannot be read', (
    tester,
  ) async {
    await pumpCanvas(
      tester,
      modelOf(
        changes: changesOf([
          Journal(
            'bad1-session',
            workflow: 'release',
            graph: const {'format': 2},
          ),
        ]),
      ),
    );
    expect(find.text('Graph of this session cannot be read'), findsOneWidget);
  });
}

/// publish() of the release fixture's call node.
Opened _publish(GraphNode call) =>
    Opened(call.id, functionId: (call as CallNode).functions.single);

/// The texts of the chips on the canvas: exit labels.
List<String> _chips(WidgetTester tester) => [
  for (final paint in tester.widgetList<CustomPaint>(find.byType(CustomPaint)))
    if (paint.painter case final ExitsPainter exits)
      for (final chip in exits.chips) chip.text,
];
