import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/graph/canvas/frame_toggle.dart';
import 'package:nanoflow_ui/graph/canvas/function_frame.dart';
import 'package:nanoflow_ui/graph/canvas/graph_canvas.dart';
import 'package:nanoflow_ui/graph/canvas/node_tile.dart';
import 'package:nanoflow_ui/state/body_path.dart';
import 'package:nanoflow_ui/state/graph_model.dart';

import '../../support/golden.dart';
import 'support.dart';

/// The docs on the canvas (node docs design §4.2): an effect's and a call's
/// tile and the title of a function's frame show the doc in a tooltip.
void main() {
  final controller = GraphCanvasController();

  /// The release fixture with docs: the workflow, publish(), the effect
  /// plan and, in publish(), upload.
  GraphFile release() => documented(
    graphFileNamed('release'),
    functions: {
      'lib/release.dart#release': 'Ships every public package.',
      'lib/publish.dart#publish':
          'Uploads [p] and takes it back when it does not verify.',
    },
    effects: {
      'lib/release.dart#release/1': 'Plans the release: what goes out.',
      'lib/publish.dart#publish/1': 'Puts the package up.',
    },
  );

  Future<GraphModel> pumpCanvas(
    WidgetTester tester,
    GraphFile graph, {
    OpenNode? onOpenNode,
  }) async {
    final model = modelOf(graph: graph);
    await pumpScreen(
      tester,
      GraphCanvas(
        model: model,
        controller: controller,
        onOpenNode: onOpenNode,
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
    return model;
  }

  Finder tile(String id) => find.byKey(NodeTile.tileKeyOf(id));
  Finder shown(String text) => find.text(text, findRichText: true);
  Finder tooltipOver(Finder finder) =>
      find.ancestor(of: finder, matching: find.byType(Tooltip));

  testWidgets('an effect\'s tile shows its doc; one without a doc has no '
      'tooltip', (tester) async {
    await pumpCanvas(tester, release());
    expect(tooltipOver(tile('3')), findsNothing);
    await hover(tester, tile('1'));
    expect(shown('Plans the release: what goes out.'), findsOneWidget);
  });

  testWidgets('a call\'s tile shows the doc of its function, a Dart '
      'reference in it without brackets', (tester) async {
    await pumpCanvas(tester, release());
    await hover(tester, tile('5'));
    expect(
      shown('Uploads p and takes it back when it does not verify.'),
      findsOneWidget,
    );
  });

  testWidgets('a call to undocumented functions has no tooltip', (
    tester,
  ) async {
    await pumpCanvas(tester, graphFileNamed('release'));
    expect(tooltipOver(tile('5')), findsNothing);
    expect(tooltipOver(tile('1')), findsNothing);
  });

  testWidgets('a call of an interface method shows each documented '
      'function under its title', (tester) async {
    await pumpCanvas(
      tester,
      documented(
        graphFileNamed('interfaces'),
        functions: {
          'lib/deploy.dart#ChatNotifier.notify': 'Posts to the channel.',
          'lib/deploy.dart#MailNotifier.notify': 'Mails the owners.',
        },
      ),
    );
    await hover(tester, tile('2'));
    expect(
      shown(
        'ChatNotifier.notify()\nPosts to the channel.\n\n'
        'MailNotifier.notify()\nMails the owners.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the title of a function\'s frame shows its doc', (tester) async {
    await pumpCanvas(tester, release());
    await tester.tap(find.byKey(FrameToggle.expandKeyOf('5')));
    await tester.pump();
    await settle(tester);
    expect(find.byType(FunctionFrameView), findsOneWidget);
    final mouse = await hover(tester, find.text('publish()'));
    expect(
      shown('Uploads p and takes it back when it does not verify.'),
      findsOneWidget,
    );
    // Its effects show theirs.
    await hover(tester, tile('5/1'), mouse);
    expect(shown('Puts the package up.'), findsOneWidget);
  });

  testWidgets('a doc in its tooltip over a call: paragraphs, a list, code', (
    tester,
  ) async {
    // The tooltip's shadow, which tests leave out unless told; set back
    // before the test ends, or the test fails.
    debugDisableShadows = false;
    try {
      await pumpCanvas(
        tester,
        documented(
          graphFileNamed('release'),
          functions: {
            'lib/publish.dart#publish':
                'Uploads [p] and takes it back when it does not verify.\n\n'
                '- `upload` puts it up\n'
                '- `rollback` takes it back, **only** when *verify* fails',
          },
        ),
      );
      await hover(tester, tile('5'));
      await expectGolden(tester, 'canvas_doc_tooltip');
    } finally {
      debugDisableShadows = true;
    }
  });

  testWidgets('the tooltip opens under the tile, at any scale, leaving the '
      'tile in sight', (tester) async {
    await pumpCanvas(tester, release());
    Rect box() => tester.getRect(
      find
          .ancestor(
            of: shown('Plans the release: what goes out.'),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    var mouse = await hover(tester, tile('1'));
    expect(box().top, greaterThan(tester.getRect(tile('1')).bottom));

    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(seconds: 1));
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
    }
    controller.revealNode('1');
    await settle(tester);
    expect(controller.scale, greaterThan(1.5));
    mouse = await hover(tester, tile('1'), mouse);
    expect(box().top, greaterThan(tester.getRect(tile('1')).bottom));
  });

  testWidgets('a documented tile still opens on a double click', (
    tester,
  ) async {
    final opened = <String>[];
    await pumpCanvas(
      tester,
      release(),
      onOpenNode: (path, node, at) => opened.add(node.id),
    );
    await tester.tap(tile('5'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(tile('5'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(opened, ['5']);
  });
}
