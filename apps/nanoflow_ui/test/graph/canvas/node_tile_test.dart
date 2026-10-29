import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/graph/canvas/canvas_style.dart';
import 'package:nanoflow_ui/graph/canvas/frame_toggle.dart';
import 'package:nanoflow_ui/graph/canvas/layout_geometry.dart';
import 'package:nanoflow_ui/graph/canvas/node_tile.dart';
import 'package:nanoflow_ui/graph/canvas/open_as_graph_button.dart';
import 'package:nanoflow_ui/graph/canvas/tile_marks.dart';
import 'package:nanoflow_ui/layout/layout.dart'
    show LayoutOptions, NodeBox, endMarker, layoutBody, startMarker;
import 'package:nanoflow_ui/state/graph_marks.dart';
import 'package:nanoflow_ui/theme.dart';
import 'package:nanoflow_ui/widgets/dashed_border.dart';
import 'package:nanoflow_ui/widgets/doc_text.dart';
import 'package:nanoflow_ui/widgets/icons.dart';
import 'package:nanoflow_ui/widgets/spinner.dart';

import '../../support/golden.dart';

void main() {
  // An effect, a condition and a call, between the markers.
  final layout = layoutBody(
    const GraphBody(
      nodes: [
        EffectNode(id: 'effect', place: 'lib/a.dart:3', name: 'collect'),
        ConditionNode(id: 'if', place: 'lib/a.dart:4', label: 'ok'),
        CallNode(
          id: 'call',
          place: 'lib/a.dart:5',
          functions: ['lib/b.dart#f'],
        ),
        ConditionNode(
          id: 'long',
          place: 'lib/a.dart:7',
          label: 'change.path.isEmpty && change.id.isNotEmpty',
        ),
      ],
      edges: [
        GraphEdge(from: null, to: 'effect', label: null),
        GraphEdge(from: 'effect', to: 'if', label: null),
        GraphEdge(from: 'if', to: 'call', label: 'true'),
        GraphEdge(from: 'if', to: null, label: 'false'),
        GraphEdge(from: 'call', to: null, label: null),
      ],
    ),
    functions: const {
      'lib/b.dart#f': GraphFunction(
        id: 'lib/b.dart#f',
        name: 'f',
        place: null,
        body: GraphBody(
          nodes: [EffectNode(id: '1', place: null, name: 'one')],
          edges: [],
        ),
      ),
    },
    options: const LayoutOptions(measure: measureLabel),
  );

  Future<void> pumpTile(
    WidgetTester tester,
    String id, {
    VoidCallback? onTap,
    ValueChanged<Offset>? onDoubleTap,
    InlineSpan? doc,
    NodeMarks? marks,
    ValueChanged<Offset>? onExpand,
    ValueChanged<Offset>? onOpenAsGraph,
  }) {
    final node = layout.nodes[id]!;
    return pumpScreen(
      tester,
      Stack(
        children: [
          Positioned.fromRect(
            rect: NodeTile.areaOf(node).shift(const Offset(100, 100)),
            child: NodeTile(
              node: node,
              onTap: onTap,
              onDoubleTap: onDoubleTap,
              doc: doc,
              marks: marks,
              onExpand: onExpand,
              onOpenAsGraph: onOpenAsGraph,
            ),
          ),
        ],
      ),
    );
  }

  Rect tileOf(WidgetTester tester, String id) =>
      tester.getRect(find.byKey(NodeTile.tileKeyOf(id)));

  /// Checks that [tile] has the function icon on it, no other, with the
  /// effects [count] under it, smaller than the name and muted: the two of
  /// them in the middle of the tile. Returns where the icon is.
  Rect expectFunction(WidgetTester tester, Rect tile, String count) {
    expect(find.byType(EffectIcon), findsNothing);
    expect(find.byType(ConditionIcon), findsNothing);
    final iconFinder = find.byType(FunctionIcon);
    expect(iconFinder, findsOneWidget);
    final icon = tester.getRect(iconFinder);
    expect(icon.size, const Size.square(28));
    final effects = find.text(count);
    expect(effects, findsOneWidget);
    final text = tester.getRect(effects);
    expect(tile.intersect(icon), icon);
    expect(tile.intersect(text), text);
    expect(text.top, greaterThanOrEqualTo(icon.bottom));
    expect(icon.center.dx, moreOrLessEquals(tile.center.dx));
    expect(text.center.dx, moreOrLessEquals(tile.center.dx));
    expect(
      (icon.top + text.bottom) / 2,
      moreOrLessEquals(tile.center.dy, epsilon: 1),
    );
    final style = tester.widget<Text>(effects).style!;
    expect(style.fontSize, lessThan(CanvasText.name.fontSize!));
    final iconColor = tester.widget<FunctionIcon>(iconFinder).color;
    expect(
      Color.alphaBlend(style.color!, CanvasColors.tileFill).computeLuminance(),
      lessThan(iconColor.computeLuminance()),
      reason: 'the count is muted against the icon',
    );
    return icon;
  }

  testWidgets('an effect: a terminal, its name and place under it', (
    tester,
  ) async {
    await pumpTile(tester, 'effect');
    expect(find.byType(EffectIcon), findsOneWidget);
    expect(find.byType(ConditionIcon), findsNothing);
    expect(find.byType(FunctionIcon), findsNothing);
    expect(find.text('collect'), findsOneWidget);
    expect(find.text('a.dart:3'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('collect')).dy,
      greaterThan(tileOf(tester, 'effect').bottom),
    );
  });

  testWidgets('a condition: the branch in the middle of its tile, its label '
      'as its name', (tester) async {
    await pumpTile(tester, 'if');
    final icon = find.byType(ConditionIcon);
    expect(icon, findsOneWidget);
    expect(find.byType(EffectIcon), findsNothing);
    expect(find.byType(FunctionIcon), findsNothing);
    expect(tester.getSize(icon), const Size.square(28));
    expect(tester.getCenter(icon), tileOf(tester, 'if').center);
    expect(find.text('ok'), findsOneWidget);
  });

  testWidgets('a call: one tile, ƒ on it with the effects of its function '
      'under it, + in its top right corner clear of them, its name with ()', (
    tester,
  ) async {
    await pumpTile(tester, 'call', onExpand: (_) {});
    final tile = tileOf(tester, 'call');
    final icon = expectFunction(tester, tile, '{ 1 }');
    final toggle = tester.getRect(find.byKey(FrameToggle.expandKeyOf('call')));
    expect(toggle.right, moreOrLessEquals(tile.right - 4));
    expect(toggle.top, moreOrLessEquals(tile.top + 4));
    expect(toggle.overlaps(icon), isFalse);
    expect(find.text('f()'), findsOneWidget);
  });

  testWidgets('a call that ran more than once says how many times over its '
      'top right corner, clear of its + and ↗', (tester) async {
    const marks = NodeMarks(state: NodeState.visited, effects: 121, calls: 5);
    await pumpTile(
      tester,
      'call',
      marks: marks,
      onExpand: (_) {},
      onOpenAsGraph: (_) {},
    );
    expect(find.text('121×'), findsNothing);
    final badge = tester.getRect(find.byType(CountBadge));
    final tile = tileOf(tester, 'call');
    expect(find.text('5×'), findsOneWidget);
    expect(badge.right, moreOrLessEquals(tile.right + 6, epsilon: 1));
    expect(badge.top, lessThan(tile.top));
    for (final button in [
      find.byKey(FrameToggle.expandKeyOf('call')),
      find.byKey(OpenAsGraphButton.keyOf('call')),
    ]) {
      expect(badge.overlaps(tester.getRect(button)), isFalse);
    }

    // Ran once: nothing over it.
    await pumpTile(
      tester,
      'call',
      marks: const NodeMarks(state: NodeState.visited, effects: 3, calls: 1),
    );
    expect(find.byType(CountBadge), findsNothing);
  });

  testWidgets('a call opens as the main graph from ↗, Open as graph, left of '
      'its + in its corner, as large as it and clear of ƒ', (tester) async {
    Offset? at;
    await pumpTile(
      tester,
      'call',
      onExpand: (_) {},
      onOpenAsGraph: (position) => at = position,
    );
    final icon = tester.getRect(find.byType(FunctionIcon));
    final toggle = tester.getRect(find.byKey(FrameToggle.expandKeyOf('call')));
    final button = find.byKey(OpenAsGraphButton.keyOf('call'));
    final open = tester.getRect(button);
    expect(open.size, toggle.size);
    expect(open.top, moreOrLessEquals(toggle.top));
    expect(open.right, moreOrLessEquals(toggle.left));
    // The strokes of ƒ keep 5.5 of its 28 units in from its box.
    expect(open.overlaps(icon.deflate(5.5)), isFalse);
    expect(find.byTooltip('Open as graph'), findsOneWidget);
    expect(find.byType(OpenOutIcon), findsOneWidget);

    await tester.tap(button);
    expect(at, isNotNull);
  });

  testWidgets('without a +, ↗ takes its place in the corner', (tester) async {
    await pumpTile(tester, 'call', onOpenAsGraph: (_) {});
    final tile = tileOf(tester, 'call');
    final open = tester.getRect(find.byKey(OpenAsGraphButton.keyOf('call')));
    expect(open.right, moreOrLessEquals(tile.right - 4));
    expect(open.top, moreOrLessEquals(tile.top + 4));
  });

  group('with a session', () {
    BoxDecoration tileLook(WidgetTester tester, String id) =>
        tester
                .widget<DecoratedBox>(find.byKey(NodeTile.tileKeyOf(id)))
                .decoration
            as BoxDecoration;

    testWidgets('an effect is framed in the state of its effects, its badge on '
        'its corner; entered twice, it says 2×', (tester) async {
      await pumpTile(
        tester,
        'effect',
        marks: const NodeMarks(state: NodeState.visited, effects: 2),
      );
      expect(
        tileLook(tester, 'effect').border!.top.color,
        const Color(0xFF3CC47C),
      );
      expect(find.text('2×'), findsOneWidget);

      await pumpTile(
        tester,
        'effect',
        marks: const NodeMarks(state: NodeState.notVisited, effects: 0),
      );
      expect(
        tileLook(tester, 'effect').border!.top.color,
        const Color(0xFF45464C),
      );
      expect(find.text('2×'), findsNothing);
    });

    testWidgets(
      'an effect running turns its sign; one interrupted, its process '
      'gone (owner spec §6), is framed in a muted grey, a pause on its '
      'corner that does not turn',
      (tester) async {
        await pumpTile(
          tester,
          'effect',
          marks: const NodeMarks(state: NodeState.running, effects: 1),
        );
        expect(find.byType(Spinner), findsOneWidget);
        expect(
          tileLook(tester, 'effect').border!.top.color,
          const Color(0xFFF2A93B),
        );

        await pumpTile(
          tester,
          'effect',
          marks: const NodeMarks(state: NodeState.interrupted, effects: 1),
        );
        expect(find.byType(Spinner), findsNothing);
        expect(
          tileLook(tester, 'effect').border!.top.color,
          AppColors.interrupted,
        );
        expect(tileLook(tester, 'effect').color, CanvasColors.tileFill);
        final badge = tester.widget<StateBadge>(find.byType(StateBadge));
        expect(badge.mark, BadgeMark.pause);
        expect(badge.fill, AppColors.interrupted);
      },
    );

    testWidgets('a fork the code went through looks as a visited effect: '
        'framed green, a check on its corner; gone through twice, it says '
        '2×', (tester) async {
      const passed = NodeMarks(state: NodeState.visited, effects: 2);
      await pumpTile(tester, 'if', marks: passed);
      expect(tileLook(tester, 'if').border!.top.color, const Color(0xFF3CC47C));
      expect(tileLook(tester, 'if').border!.top.width, 2);
      expect(
        tester.widget<StateBadge>(find.byType(StateBadge)).mark,
        BadgeMark.check,
      );
      expect(find.byType(ConditionIcon), findsOneWidget);
      expect(find.text('2×'), findsOneWidget);

      // No marks: plain, as with no session.
      await pumpTile(tester, 'if');
      expect(tileLook(tester, 'if').border!.top.color, CanvasColors.tileBorder);
      expect(find.byType(StateBadge), findsNothing);
    });

    testWidgets('the ring of the selected effect\'s node is round its tile', (
      tester,
    ) async {
      final node = layout.nodes['effect']!;
      await pumpScreen(
        tester,
        Stack(children: [NodeTile.ringOf(node, 'effect')]),
      );
      final ring = find.byKey(NodeTile.ringKeyOf('effect'));
      expect(
        tester.getSize(ring),
        node.tile.toRect().inflate(NodeTile.ring).size,
      );
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: ring, matching: find.byType(DecoratedBox)),
      );
      expect((box.decoration as BoxDecoration).color, CanvasColors.ring);
    });

    testWidgets('a running call: its ƒ and the effects under it in the look '
        'of running effects', (tester) async {
      await pumpTile(
        tester,
        'call',
        marks: const NodeMarks(state: NodeState.running, effects: 1, calls: 1),
      );
      expect(
        tester.widget<FunctionIcon>(find.byType(FunctionIcon)).color,
        TileLook.running.icon,
      );
      expect(
        tester.widget<Text>(find.text('{ 1 }')).style!.color,
        TileLook.running.inside,
      );
    });
  });

  testWidgets('a name cut short is whole in its tooltip', (tester) async {
    await pumpTile(tester, 'long');
    expect(find.text('change.path.isEmpty && change…'), findsOneWidget);
    expect(
      find.byTooltip('change.path.isEmpty && change.id.isNotEmpty'),
      findsOneWidget,
    );
    await pumpTile(tester, 'effect');
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('the markers: dashed, saying start and end, nothing under', (
    tester,
  ) async {
    for (final (id, text) in [(startMarker, 'start'), (endMarker, 'end')]) {
      await pumpTile(tester, id);
      expect(
        find.descendant(
          of: find.byKey(NodeTile.tileKeyOf(id)),
          matching: find.text(text),
        ),
        findsOneWidget,
      );
      expect(find.byType(DashedBorder), findsOneWidget);
      expect(find.byType(Text), findsOneWidget);
    }
  });

  testWidgets('a double click tells where it was; a tile nothing opens takes '
      'no clicks', (tester) async {
    final at = <Offset>[];
    await pumpTile(tester, 'call', onDoubleTap: at.add);
    final centre = tester.getCenter(find.byKey(NodeTile.tileKeyOf('call')));
    await tester.tap(find.byKey(NodeTile.tileKeyOf('call')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byKey(NodeTile.tileKeyOf('call')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(at, [centre]);

    await pumpTile(tester, 'effect');
    expect(
      find.descendant(
        of: find.byType(NodeTile),
        matching: find.byType(MouseRegion),
      ),
      findsNothing,
    );
  });

  testWidgets('a tile with a doc takes a click and a double click as one '
      'without', (tester) async {
    var taps = 0;
    final at = <Offset>[];
    await pumpTile(
      tester,
      'call',
      onTap: () => taps++,
      onDoubleTap: at.add,
      doc: docSpan('Publishes it.'),
    );
    expect(find.byType(Tooltip), findsOneWidget);
    final tile = find.byKey(NodeTile.tileKeyOf('call'));
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 500));
    expect(taps, 1);
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 500));
    expect(at, [tester.getCenter(tile)]);
  });

  test('a node\'s area holds its tile and its texts', () {
    for (final NodeBox node in layout.nodes.values) {
      final area = NodeTile.areaOf(node);
      for (final rect in [node.tile, node.nameRect, node.placeRect]) {
        expect(area.intersect(rect.toRect()), rect.toRect());
      }
    }
  });
}
