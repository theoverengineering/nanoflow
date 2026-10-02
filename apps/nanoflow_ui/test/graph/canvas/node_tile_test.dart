import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart' hide Route;
import 'package:nanoflow_ui/graph/canvas/canvas_style.dart';
import 'package:nanoflow_ui/graph/canvas/node_tile.dart';
import 'package:nanoflow_ui/layout/layout.dart' show LayoutOptions, layoutGraph;
import 'package:nanoflow_ui/state/graph_marks.dart';
import 'package:nanoflow_ui/state/runs.dart';

import '../../support/golden.dart';

void main() {
  final node = layoutGraph(
    Graph.fromJson(const {
      'start': 'only',
      'nodes': {
        'only': {'command': 'only.sh'},
      },
    }),
    options: const LayoutOptions(measure: measureLabel),
  ).nodes['only']!;

  final aaaa = RunMarker('aaaa-run', RunPhase.running);
  final bbbb = RunMarker('bbbb-run', RunPhase.finished);
  final cccc = RunMarker('cccc-run', RunPhase.failed);

  Future<void> pumpTile(
    WidgetTester tester,
    List<RunMarker> markers, {
    String? visits,
    String? selectedRun,
  }) => pumpScreen(
    tester,
    Stack(
      children: [
        Positioned.fromRect(
          rect: NodeTile.areaOf(node).shift(const Offset(100, 100)),
          child: NodeTile(
            node: node,
            state: NodeState.visited,
            markers: markers,
            visits: visits,
            selectedRun: selectedRun,
          ),
        ),
      ],
    ),
  );

  /// The row of badges over the tile, which [text] is in, on screen.
  Rect rowOf(WidgetTester tester, String text) => tester.getRect(
    find.ancestor(of: find.text(text), matching: find.byType(Row)).first,
  );

  /// Whether the badge row is over the tile, reaching at most 6 px past its
  /// sides, and inside what the node's widget takes, where it is hit.
  void expectOverTile(WidgetTester tester, Rect row) {
    final tile = tester.getRect(find.byKey(NodeTile.tileKeyOf('only')));
    final area = tester.getRect(find.byKey(NodeTile.keyOf('only')));
    expect(row.left, greaterThanOrEqualTo(tile.left - 6 - 0.01));
    expect(row.right, lessThanOrEqualTo(tile.right + 6 + 0.01));
    expect(area.intersect(row), row);
  }

  String tooltipOf(WidgetTester tester, String text) => tester
      .widget<Tooltip>(
        find.ancestor(of: find.text(text), matching: find.byType(Tooltip)),
      )
      .message!;

  testWidgets('shows every run on the node when they fit over the tile', (
    tester,
  ) async {
    await pumpTile(tester, [aaaa, bbbb]);
    expect(find.text('aaaa'), findsOneWidget);
    expect(find.text('bbbb'), findsOneWidget);
    expect(tooltipOf(tester, 'bbbb'), 'bbbb-run');
    expectOverTile(tester, rowOf(tester, 'aaaa'));
  });

  testWidgets('collapses runs that do not fit into the first with how many '
      'more, every id in its tooltip', (tester) async {
    await pumpTile(tester, [aaaa, bbbb, cccc], visits: '2×');
    expect(find.text('aaaa +2'), findsOneWidget);
    expect(find.text('bbbb'), findsNothing);
    expect(find.text('2×'), findsOneWidget);
    expect(tooltipOf(tester, 'aaaa +2'), 'aaaa-run\nbbbb-run\ncccc-run');
    expectOverTile(tester, rowOf(tester, 'aaaa +2'));
  });

  testWidgets('with the visit count two runs do not fit', (tester) async {
    await pumpTile(tester, [aaaa, bbbb], visits: '3×');
    expect(find.text('aaaa +1'), findsOneWidget);
    expectOverTile(tester, rowOf(tester, '3×'));
  });

  testWidgets('collapses into the selected run when it is on the node', (
    tester,
  ) async {
    await pumpTile(tester, [aaaa, bbbb, cccc], selectedRun: 'cccc-run');
    expect(find.text('cccc +2'), findsOneWidget);
    expect(tooltipOf(tester, 'cccc +2'), 'aaaa-run\nbbbb-run\ncccc-run');
  });
}
