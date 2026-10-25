import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/graph/canvas/canvas_marks.dart';
import 'package:nanoflow_ui/graph/canvas/canvas_style.dart';
import 'package:nanoflow_ui/graph/canvas/copies_frame.dart';
import 'package:nanoflow_ui/graph/canvas/edges_painter.dart';
import 'package:nanoflow_ui/graph/canvas/exit_labels.dart';
import 'package:nanoflow_ui/graph/canvas/frame_toggle.dart';
import 'package:nanoflow_ui/graph/canvas/function_frame.dart';
import 'package:nanoflow_ui/graph/canvas/graph_canvas.dart';
import 'package:nanoflow_ui/graph/canvas/layout_geometry.dart';
import 'package:nanoflow_ui/graph/canvas/node_tile.dart';
import 'package:nanoflow_ui/graph/canvas/open_as_graph_button.dart';
import 'package:nanoflow_ui/graph/copy_switcher.dart';
import 'package:nanoflow_ui/graph/header.dart';
import 'package:nanoflow_ui/graph/logs/effect_list.dart';
import 'package:nanoflow_ui/graph/logs/logs_panel.dart';
import 'package:nanoflow_ui/layout/layout.dart' as layout;
import 'package:nanoflow_ui/state/body_path.dart';
import 'package:nanoflow_ui/state/graph_marks.dart';
import 'package:nanoflow_ui/state/graph_model.dart';

import '../../layout/support.dart'
    show bodyOf, callThenWait, functionOf, loadGraphFile;
import '../../state/support.dart';
import '../../support/golden.dart';
import '../logs/support.dart';
import '../support.dart';
import 'support.dart';

void main() {
  final controller = GraphCanvasController();

  /// The canvas of [model]; a `+` expands as its node alone opens, a ↗
  /// is [onOpenAsGraph].
  Future<void> pumpCanvas(
    WidgetTester tester,
    GraphModel model, {
    OpenNode? onOpenAsGraph,
  }) async {
    await pumpScreen(
      tester,
      GraphCanvas(
        model: model,
        controller: controller,
        onOpenAsGraph: onOpenAsGraph,
        onExpandNode: (path, node, _) async {
          model.expandNode(
            path,
            openings(node, model.canvas.file!.functions).first,
          );
          return true;
        },
      ),
      size: reviewCanvas,
    );
    await settle(tester);
  }

  Finder node(String id) => find.byKey(NodeTile.keyOf(id));
  Finder tile(String id) => find.byKey(NodeTile.tileKeyOf(id));
  Finder expand(String id) => find.byKey(FrameToggle.expandKeyOf(id));
  Finder collapse(String id) => find.byKey(FrameToggle.collapseKeyOf(id));
  Finder openAsGraph(String id) => find.byKey(OpenAsGraphButton.keyOf(id));

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
    expect(expand('1'), findsNothing, reason: 'an effect does not expand');

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

  testWidgets('↗ is on calls alone, not on effects, forks or copies; in a '
      'frame too, opening from there', (tester) async {
    final opened = <(String, String)>[];
    await pumpCanvas(
      tester,
      modelOf(
        graph: GraphFile.fromJson({
          ...graphFileNamed('inline').toJson(),
          'workflows': ['lib/inline.dart#viaCall'],
        }),
      ),
      onOpenAsGraph: (path, node, _) => opened.add((levelKey(path), node.id)),
    );
    expect(openAsGraph('1'), findsNothing, reason: 'copies');
    await tap(tester, expand('1'));
    expect(openAsGraph('1/1'), findsOneWidget);
    await tap(tester, openAsGraph('1/1'));
    expect(opened, [
      (levelKey(const [Opened('1')]), '1'),
    ]);

    await pumpCanvas(tester, modelOf(), onOpenAsGraph: (_, _, _) {});
    expect(openAsGraph('5'), findsOneWidget);
    expect(openAsGraph('1'), findsNothing, reason: 'an effect');
    expect(openAsGraph('2'), findsNothing, reason: 'a fork');
  });

  testWidgets('the end of a function in place is a bar on the frame\'s right '
      'side, outlined as a tile\'s bar: the arrows that end the body point '
      'at it, the frame has no exit dot; a tile keeps its dot', (tester) async {
    await pumpCanvas(tester, modelOf());
    await tap(tester, expand('5'));

    /// The paint of a painter of type [T] that [which] picks: the level's,
    /// or the body's in the frame.
    CustomPaint painting<T extends CustomPainter>(bool Function(T) which) =>
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .firstWhere(
              (paint) => paint.painter is T && which(paint.painter! as T),
            );
    bool level(layout.GraphLayout graph) => graph.nodes['5']?.frame != null;
    bool body(layout.GraphLayout graph) =>
        graph.nodes[layout.endMarker]?.port ?? false;
    RenderObject render(CustomPaint paint) =>
        tester.renderObject(find.byWidget(paint));

    final lines = painting<EdgesPainter>((p) => level(p.graph));
    final graph = (lines.painter! as EdgesPainter).graph;
    final inner = graph.nodes['5']!.frame!.inner;
    final bar = inner.nodes[layout.endMarker]!.bar!.rect.toRect();
    expect(
      render(lines),
      paints
        ..something(
          (method, args) =>
              method == #drawRRect &&
              args[0] ==
                  RRect.fromRectAndRadius(
                    bar.inflate(1),
                    const Radius.circular(3),
                  ) &&
              (args[1] as Paint).color.toARGB32() ==
                  CanvasColors.background.toARGB32(),
        )
        ..rrect(
          rrect: RRect.fromRectAndRadius(bar, const Radius.circular(2)),
          color: CanvasColors.plain,
        ),
    );
    final ends = inner.edges.where((e) => e.to == layout.endMarker);
    expect(ends, hasLength(2));
    for (final edge in ends) {
      final head = edge.tip.toOffset() - const Offset(3, 0);
      expect(
        render(painting<EdgesPainter>((p) => body(p.graph))),
        paints..something(
          (method, args) =>
              method == #drawPath && (args[0] as Path).contains(head),
        ),
        reason: 'the head of the arrow from ${edge.from}',
      );
    }

    final exits = render(painting<ExitsPainter>((p) => level(p.graph)));
    Offset anchorOf(String id) =>
        graph.exits.singleWhere((x) => x.node == id).anchor.toOffset();
    final out = anchorOf('5');
    expect(
      exits,
      paints
        ..everything((method, args) => method != #drawCircle || args[0] != out),
    );
    final plan = anchorOf('1');
    expect(
      exits,
      paints
        ..something((method, args) => method == #drawCircle && args[0] == plan)
        ..circle(
          x: plan.dx,
          y: plan.dy,
          radius: 4.5,
          color: CanvasColors.plain,
        ),
    );
  });

  testWidgets('a frame whose body has no end has no bar there: its arrow '
      'out leaves an exit dot, as a tile\'s does', (tester) async {
    final release = loadGraphFile('release');
    final graph = layout.layoutBody(
      functionOf(release, 'release').body,
      functions: release.functions,
      expanded: {
        '5': layout.ExpandedNode(
          bodyOf({
            'start': 'a',
            'nodes': {
              'a': {'command': true},
            },
          }),
        ),
      },
    );
    expect(graph.nodes['5']!.frame!.endBar, isNull);
    await tester.pumpWidget(
      CustomPaint(painter: ExitsPainter(graph, CanvasMarks.plain)),
    );
    final out = graph.exits.singleWhere((x) => x.node == '5').anchor;
    expect(
      tester.renderObject(find.byType(CustomPaint)),
      paints
        ..something(
          (method, args) => method == #drawCircle && args[0] == out.toOffset(),
        )
        ..circle(x: out.x, y: out.y, radius: 4.5, color: CanvasColors.plain),
    );
  });

  testWidgets('a frame whose way out is a capsule, branches of Future.wait '
      'after the call, draws no capsule: the bar of its body\'s end is its '
      'exit; a tile\'s capsule stays', (tester) async {
    layout.GraphLayout laid({required bool inPlace}) => layout.layoutBody(
      callThenWait(2),
      expanded: {
        if (inPlace)
          'c': layout.ExpandedNode(
            bodyOf({
              'start': 'a',
              'nodes': {
                'a': {'command': true, 'then': <Object?>[]},
              },
            }),
          ),
      },
    );

    /// What the exits of [graph] paint: a capsule round the exit of c or
    /// none.
    Future<RenderObject> exitsOf(layout.GraphLayout graph) async {
      await tester.pumpWidget(
        CustomPaint(painter: ExitsPainter(graph, CanvasMarks.plain)),
      );
      return tester.renderObject(find.byType(CustomPaint));
    }

    /// A capsule painted round the exit of c in [graph].
    Object capsuleOf(layout.GraphLayout graph) {
      final out = graph.exits.singleWhere((x) => x.node == 'c');
      expect(out.shape, layout.ExitShape.capsule);
      final anchor = out.anchor.toOffset();
      return paints..something(
        (method, args) =>
            method == #drawRRect &&
            (args[0] as RRect).outerRect.contains(anchor),
      );
    }

    final tile = laid(inPlace: false);
    expect(await exitsOf(tile), capsuleOf(tile));
    final framed = laid(inPlace: true);
    expect(framed.nodes['c']!.frame!.endBar, isNotNull);
    expect(await exitsOf(framed), isNot(capsuleOf(framed)));
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

  testWidgets('a session on a call in place: the effects of its function on '
      'their nodes in the frame, the selected one ringed', (tester) async {
    final release = graphFileNamed('release');
    final j =
        Journal('r1r1-session', workflow: 'release', graph: release.toJson())
          ..effect('plan', 1, end: 2, place: 'lib/release.dart:16')
          ..effect('upload', 3, end: 4, place: 'lib/publish.dart:12')
          ..effect('verify', 5, place: 'lib/publish.dart:13');
    final model = modelOf(changes: j.changes);
    await pumpCanvas(tester, model);
    await tap(tester, expand('5'));
    NodeTile tileOf(String id) => tester.widget<NodeTile>(node(id));
    expect(tileOf('5/1').marks!.state, NodeState.visited);
    expect(tileOf('5/2').marks!.state, NodeState.running);
    expect(find.byKey(NodeTile.ringKeyOf('5/2')), findsOneWidget);
    expect(find.byKey(NodeTile.ringKeyOf('5')), findsNothing);
    expect(tileOf('5/4').marks!.state, NodeState.notVisited);
    expect(tileOf('1').marks!.state, NodeState.visited);
  });

  testWidgets('what a session changes in a frame — the room of its copy '
      'switcher — keeps the view fitted as it was', (tester) async {
    final model = modelOf(
      graph: graphFileNamed('inline'),
      file: inlineFile,
      changes: copiesSession().changes,
    );
    model.selection.showCurrentGraph();
    await pumpCanvas(tester, model);
    await tap(tester, expand('1'));
    final (scale, offset) = (controller.scale, controller.offset);

    // The session's frame has its switcher: a row taller.
    model.showSession('c0c0-session');
    await settle(tester);
    expect(find.byType(CopySwitcher), findsOneWidget);
    expect(controller.scale, scale);
    expect(controller.offset, offset);
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

    testWidgets('↗ on a call opens its function as the main graph: the '
        'crumbs start at it', (tester) async {
      final model = await pumpGraphScreen(tester);
      await tap(tester, openAsGraph('5'));
      expect(model.workflow!.id, 'lib/publish.dart#publish');
      expect(
        find.descendant(
          of: find.byType(GraphHeader),
          matching: find.text('publish'),
        ),
        findsOneWidget,
      );
      expect(tile('1'), findsOneWidget);
      expect(find.text('upload'), findsOneWidget);
    });

    testWidgets('↗ on a call of an interface method offers its '
        'implementations; the one chosen opens', (tester) async {
      final model = await pumpGraphScreen(
        tester,
        model: ownedModel(
          file: releaseFile,
          graph: graphFileNamed('interfaces'),
        ),
      );
      await tap(tester, openAsGraph('2'));
      await tester.tap(find.text('MailNotifier.notify()').last);
      await tester.pumpAndSettle();
      expect(model.workflow!.id, _mail);
      expect(find.text('send-mail'), findsOneWidget);
    });

    testWidgets('a + whose menu is left without a choice expands nothing, '
        'and moves nothing later', (tester) async {
      final model = await pumpGraphScreen(
        tester,
        model: ownedModel(
          file: releaseFile,
          graph: graphFileNamed('interfaces'),
        ),
      );
      await tester.drag(find.byType(GraphCanvas), const Offset(-60, 20));
      await tester.pump();
      final opened = tester.getTopLeft(tile('2'));
      await tap(tester, expand('2'));
      expect(find.text('MailNotifier.notify()'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('MailNotifier.notify()'), findsNothing);
      expect(model.canvas.frames, isEmpty);

      // The view moved on; the call expanded otherwise is not put back
      // where its tile was when the menu opened.
      await tester.drag(find.byType(GraphCanvas), const Offset(-80, 0));
      await tester.pump();
      model.expandNode(const [], const Opened('2', functionId: _mail));
      await settle(tester);
      expect(
        tester.getTopLeft(find.byType(FunctionFrameView)).dx,
        isNot(closeTo(opened.dx, 1)),
      );
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
      // How many copies are on each effect now.
      expect(find.byKey(NodeTile.runningKeyOf('1/2')), findsOneWidget);
      expect(find.byKey(NodeTile.runningKeyOf('1/3')), findsOneWidget);

      await tap(tester, find.byKey(CopySwitcher.chipKey(2)));
      expect(
        textIn(tester, find.byKey(CopiesFrameView.footerKey)),
        'pkg 2 · now verify',
      );
      expect(
        textIn(tester, find.byKey(LogsPanel.titleKey)),
        'Logs pkg 2 · 2 effects',
      );
      expect(model.selection.effectId, 'c0c0-verify-4');
      final tag = tester.widget<NodeTile>(node('1/3'));
      expect(tag.marks!.effects, 0, reason: 'tool has not reached tag');

      // Opened, the copies show the same copy.
      model.open(const Opened('1'));
      await settle(tester);
      expect(
        textIn(tester, find.byKey(CopiesFrameView.footerKey)),
        'pkg 2 · now verify',
      );
    });

    testWidgets(
      'an effect of Logs in a frame is shown at its node in the frame',
      (tester) async {
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

        await tap(tester, find.byKey(EffectList.rowKey('c0c0-upload-0')));
        expect(
          inside(canvas, tester.getRect(tile('1/1'))),
          isTrue,
          reason: 'upload is revealed in the frame',
        );
      },
    );
  });
}

const _mail = 'lib/deploy.dart#MailNotifier.notify';
