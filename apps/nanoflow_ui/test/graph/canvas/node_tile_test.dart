import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/graph/canvas/canvas_style.dart';
import 'package:nanoflow_ui/graph/canvas/layout_geometry.dart';
import 'package:nanoflow_ui/graph/canvas/node_tile.dart';
import 'package:nanoflow_ui/graph/canvas/tile_marks.dart';
import 'package:nanoflow_ui/layout/layout.dart'
    show LayoutOptions, NodeBox, endMarker, layoutBody, startMarker;
import 'package:nanoflow_ui/state/graph_marks.dart';
import 'package:nanoflow_ui/theme.dart';
import 'package:nanoflow_ui/widgets/dashed_border.dart';
import 'package:nanoflow_ui/widgets/icons.dart';
import 'package:nanoflow_ui/widgets/spinner.dart';

import '../../support/golden.dart';

void main() {
  // An effect, a condition, a call and copies, between the markers.
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
        CopiesNode(
          id: 'copies',
          place: 'lib/a.dart:6',
          label: 'x in xs',
          body: GraphBody(
            nodes: [
              EffectNode(id: '1', place: null, name: 'a'),
              EffectNode(id: '2', place: null, name: 'b'),
            ],
            edges: [],
          ),
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
        GraphEdge(from: 'if', to: 'copies', label: 'false'),
        GraphEdge(from: 'call', to: null, label: null),
        GraphEdge(from: 'copies', to: null, label: null),
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
    ValueChanged<Offset>? onDoubleTap,
    NodeMarks? marks,
    bool allCopies = false,
    String copies = '×n',
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
              onDoubleTap: onDoubleTap,
              marks: marks,
              allCopies: allCopies,
              copies: copies,
            ),
          ),
        ],
      ),
    );
  }

  Rect tileOf(WidgetTester tester, String id) =>
      tester.getRect(find.byKey(NodeTile.tileKeyOf(id)));

  /// The tiles stacked behind the tile, outermost first.
  List<Rect> stackOf(WidgetTester tester) => [
    for (final element in find.byType(DecoratedBox).evaluate())
      if ((element.widget as DecoratedBox).decoration case BoxDecoration(
        color: CanvasColors.stackFill,
      ))
        if (element.renderObject case final RenderBox box)
          box.localToGlobal(Offset.zero) & box.size,
  ];

  testWidgets('an effect: a terminal, its name and place under it', (
    tester,
  ) async {
    await pumpTile(tester, 'effect');
    expect(tester.widget<NodeIcon>(find.byType(NodeIcon)).fork, isFalse);
    expect(find.text('collect'), findsOneWidget);
    expect(find.text('a.dart:3'), findsOneWidget);
    expect(stackOf(tester), isEmpty);
    expect(
      tester.getTopLeft(find.text('collect')).dy,
      greaterThan(tileOf(tester, 'effect').bottom),
    );
  });

  testWidgets('a condition: a diamond, its label as its name', (tester) async {
    await pumpTile(tester, 'if');
    expect(tester.widget<NodeIcon>(find.byType(NodeIcon)).fork, isTrue);
    expect(find.text('ok'), findsOneWidget);
  });

  testWidgets('a call: a tile stacked behind it, over its top, the effects of '
      'its function on it, its name with ()', (tester) async {
    await pumpTile(tester, 'call');
    final tile = tileOf(tester, 'call');
    final stack = stackOf(tester);
    expect(stack, hasLength(1));
    expect(stack.single.top, lessThan(tile.top));
    expect(stack.single.left, greaterThan(tile.left));
    expect(stack.single.right, lessThan(tile.right));
    expect(find.byType(NodeIcon), findsNothing);
    expect(find.text('{ 1 }'), findsOneWidget);
    expect(find.text('f()'), findsOneWidget);
  });

  testWidgets('copies: two tiles stacked behind, the effects of a copy on '
      'them as on a call, ×n across the top right of the stack, their '
      'label', (tester) async {
    await pumpTile(tester, 'copies');
    final tile = tileOf(tester, 'copies');
    final stack = stackOf(tester);
    expect(stack, hasLength(2));
    expect(stack.first.top, lessThan(stack.last.top));
    final effects = find.text('{ 2 }');
    expect(effects, findsOneWidget);
    expect(
      tester.widget<Text>(effects).style!.fontSize,
      CanvasText.inside.fontSize,
    );
    expect(tester.getCenter(effects).dx, moreOrLessEquals(tile.center.dx));
    final badge = tester.getRect(
      find.ancestor(of: find.text('×n'), matching: find.byType(Container)),
    );
    expect(badge.center.dy, moreOrLessEquals(stack.first.top, epsilon: 1));
    expect(badge.right, moreOrLessEquals(tile.right + 6, epsilon: 1));
    expect(find.text('x in xs'), findsOneWidget);
    // All of it inside what the node's widget takes.
    final area = tester.getRect(find.byKey(NodeTile.keyOf('copies')));
    expect(area.intersect(badge), badge);
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
        marks: const NodeMarks(
          state: NodeState.visited,
          effects: 2,
          running: 0,
        ),
      );
      expect(
        tileLook(tester, 'effect').border!.top.color,
        const Color(0xFF3CC47C),
      );
      expect(find.text('2×'), findsOneWidget);

      await pumpTile(
        tester,
        'effect',
        marks: const NodeMarks(
          state: NodeState.notVisited,
          effects: 0,
          running: 0,
        ),
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
          marks: const NodeMarks(
            state: NodeState.running,
            effects: 1,
            running: 1,
          ),
        );
        expect(find.byType(Spinner), findsOneWidget);
        expect(
          tileLook(tester, 'effect').border!.top.color,
          const Color(0xFFF2A93B),
        );

        await pumpTile(
          tester,
          'effect',
          marks: const NodeMarks(
            state: NodeState.interrupted,
            effects: 1,
            running: 0,
          ),
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

    testWidgets('in the body of copies, all shown, an effect says how many '
        'copies are on it now, instead of 2×', (tester) async {
      await pumpTile(
        tester,
        'effect',
        allCopies: true,
        marks: const NodeMarks(
          state: NodeState.running,
          effects: 3,
          running: 2,
        ),
      );
      expect(
        find.descendant(
          of: find.byKey(NodeTile.runningKeyOf('effect')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(find.text('3×'), findsNothing);

      // An effect all the copies there passed: nothing over it
      // (docs/design/code-first/copies-frame.html).
      await pumpTile(
        tester,
        'effect',
        allCopies: true,
        marks: const NodeMarks(
          state: NodeState.visited,
          effects: 3,
          running: 0,
        ),
      );
      expect(find.byKey(NodeTile.runningKeyOf('effect')), findsNothing);
      expect(find.text('3×'), findsNothing);
    });

    testWidgets('a fork the code went through looks as a visited effect: '
        'framed green, a check on its corner; gone through twice, it says '
        '2×', (tester) async {
      const passed = NodeMarks(
        state: NodeState.visited,
        effects: 2,
        running: 0,
      );
      await pumpTile(tester, 'if', marks: passed);
      expect(tileLook(tester, 'if').border!.top.color, const Color(0xFF3CC47C));
      expect(tileLook(tester, 'if').border!.top.width, 2);
      expect(
        tester.widget<StateBadge>(find.byType(StateBadge)).mark,
        BadgeMark.check,
      );
      expect(tester.widget<NodeIcon>(find.byType(NodeIcon)).fork, isTrue);
      expect(find.text('2×'), findsOneWidget);

      // In the body of copies, all shown: no count over it.
      await pumpTile(tester, 'if', marks: passed, allCopies: true);
      expect(tileLook(tester, 'if').border!.top.color, const Color(0xFF3CC47C));
      expect(find.byType(StateBadge), findsOneWidget);
      expect(find.text('2×'), findsNothing);
      expect(find.byKey(NodeTile.runningKeyOf('if')), findsNothing);

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

    testWidgets('copies say how many ran, muted while none has; their stack '
        'keeps the corner: no count over it', (tester) async {
      const marks = NodeMarks(
        state: NodeState.running,
        effects: 4,
        running: 1,
        copies: 3,
      );
      await pumpTile(tester, 'copies', marks: marks, copies: '×3');
      expect(find.text('×3'), findsOneWidget);
      expect(find.text('4×'), findsNothing);
      expect(
        tester.widget<Text>(find.text('×3')).style!.color,
        CanvasColors.badgeText,
      );

      await pumpTile(
        tester,
        'copies',
        marks: const NodeMarks(
          state: NodeState.notVisited,
          effects: 0,
          running: 0,
          copies: 0,
        ),
        copies: '×0',
      );
      expect(
        tester.widget<Text>(find.text('×0')).style!.color,
        CanvasColors.markerText,
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

  test('a node\'s area holds its tile, the tiles behind it and its texts', () {
    for (final NodeBox node in layout.nodes.values) {
      final area = NodeTile.areaOf(node);
      final tile = Rect.fromLTRB(
        node.tile.left,
        node.tile.top - 14,
        node.tile.right,
        node.tile.bottom,
      );
      expect(area.intersect(tile), tile);
    }
  });
}
