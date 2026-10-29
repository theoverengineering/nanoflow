import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/body_path.dart';

import '../state/support.dart';
import '../support/golden.dart';
import 'canvas/support.dart';
import 'support.dart';

void main() {
  testWidgets('a function opened from its call, under the crumbs', (
    tester,
  ) async {
    final model = await pumpGraphScreen(tester);
    model.open(const Opened('5', functionId: 'lib/publish.dart#publish'));
    await settle(tester);
    await expectGolden(tester, 'graph_publish');
  });

  testWidgets('a called graph opened as the main graph, its crumb after the '
      "workflow's", (tester) async {
    final model = await pumpGraphScreen(tester);
    model.openAsGraph('lib/publish.dart#publish');
    await settle(tester);
    await expectGolden(tester, 'graph_called');
  });

  testWidgets('a deep path in the narrowest window: the middle crumbs '
      'folded', (tester) async {
    final model = await pumpGraphScreen(
      tester,
      model: ownedModel(file: releaseFile, graph: graphFileNamed('recursion')),
      size: const Size(1100, 700),
    );
    for (var i = 0; i < 4; i++) {
      model
        ..open(const Opened('3', functionId: 'lib/crawl.dart#visit'))
        ..open(const Opened('2', functionId: 'lib/crawl.dart#crawl'));
    }
    await settle(tester);
    await expectGolden(tester, 'graph_deep');
  });

  testWidgets('a session without a snapshot: its notes under the session '
      'bar', (tester) async {
    await pumpGraphScreen(
      tester,
      model: ownedModel(
        file: releaseFile,
        changes: changesOf([
          Journal('r1r1-session', workflow: 'release', snapshot: false)
            ..effect('plan', 1, end: 3, place: 'lib/release.dart:16')
            ..effect('build', 3, place: 'lib/release.dart:18'),
        ]),
      ),
      now: () => at(200),
    );
    await expectGolden(tester, 'graph_session');
  });

  testWidgets('a running session on its graph: its effects on the nodes, Logs '
      '(docs/design/graph.png); the forks it went through as effects design '
      '§5.3 draws them, not grey as the mockup', (tester) async {
    await pumpReview(tester);
    await expectGolden(tester, 'graph_review');
  });

  testWidgets('a finished session on its graph: the forks it went through '
      'look visited, the loop\'s twice, the way to discard it could not '
      'have taken darker (effects design §5.3)', (tester) async {
    await pumpReview(tester, model: reviewModel(finished: true));
    await expectGolden(tester, 'graph_review_passes');
  });

  testWidgets('a session whose process is gone: Interrupted on its card and '
      'bar, the effect that was running interrupted on its node and in Logs '
      '(owner spec §6)', (tester) async {
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
    await expectGolden(tester, 'graph_interrupted');
  });

  testWidgets('a running session on functions expanded in place: publish() '
      'and upload() in it, its effects on their nodes, sign() done as a tile '
      '(docs/design/code-first/function-frames.html)', (tester) async {
    final graph = framesGraphFile();
    String release(int line) => 'lib/release.dart:$line';
    String publish(int line) => 'lib/publish.dart:$line';
    final model = await pumpGraphScreen(
      tester,
      model: ownedModel(
        file: releaseFile,
        graph: graph,
        changes: changesOf([
          Journal(
              'a1b2-session',
              workflow: 'release',
              graph: graph.toJson(),
              code: graph.fingerprint,
            )
            ..effect('plan', 0, end: 20, place: release(16))
            ..effect('build', 21, end: 140, place: release(18))
            ..effect('hash', 141, end: 150, place: publish(26))
            ..effect('signature', 151, end: 170, place: publish(27))
            ..effect('put', 171, place: publish(22)),
        ]),
      ),
      now: () => columnNow,
    );
    const call = Opened('5', functionId: 'lib/publish.dart#publish');
    model
      ..expandNode(const [], call)
      ..expandNode(const [
        call,
      ], const Opened('1', functionId: 'lib/publish.dart#upload'));
    await settle(tester);
    await expectGolden(tester, 'graph_frames');
  });
}
