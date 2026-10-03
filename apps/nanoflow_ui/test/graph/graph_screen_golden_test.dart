import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/body_path.dart';

import '../state/support.dart';
import '../support/golden.dart';
import 'canvas/support.dart';
import 'support.dart';

void main() {
  /// The release fixture with publish as a workflow too.
  GraphFile twoWorkflows() => GraphFile.fromJson({
    ...graphFileNamed('release').toJson(),
    'workflows': ['lib/release.dart#release', 'lib/publish.dart#publish'],
  });

  testWidgets('a function opened from its call, under the crumbs of the '
      'workflow picker', (tester) async {
    final model = await pumpGraphScreen(
      tester,
      model: ownedModel(file: releaseFile, graph: twoWorkflows()),
    );
    model.open(const Opened('5', functionId: 'lib/publish.dart#publish'));
    await settle(tester);
    await expectGolden(tester, 'graph_publish');
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
            ..step('plan', 1, end: 3, place: 'lib/release.dart:16')
            ..step('build', 3, place: 'lib/release.dart:18'),
          Journal('d1d1-session', workflow: 'deploy', startedAt: -60),
        ]),
      ),
      now: () => at(200),
    );
    await expectGolden(tester, 'graph_session');
  });

  testWidgets('a running session on its graph: its steps on the nodes, Logs '
      '(docs/design/graph.png)', (tester) async {
    await pumpReview(tester);
    await expectGolden(tester, 'graph_review');
  });

  testWidgets('the body of copies, all of them: how many are on each step, '
      'done 1 of 3 (docs/design/code-first/copies-frame.html)', (tester) async {
    final model = await pumpGraphScreen(
      tester,
      path: inlineFile,
      model: copiesModel(),
      now: () => columnNow,
    );
    model.open(const Opened('1'));
    await settle(tester);
    await expectGolden(tester, 'graph_copies');
  });

  testWidgets('one copy: its path, pkg 2 · now verify, the ways it has '
      'not gone darker '
      '(docs/design/code-first/copy-switcher.html)', (tester) async {
    final model = await pumpGraphScreen(
      tester,
      path: inlineFile,
      model: copiesModel(),
      now: () => columnNow,
    );
    model.open(const Opened('1'));
    await settle(tester);
    model.selectCopy(1, 'c0c0-upload-1');
    await settle(tester);
    await expectGolden(tester, 'graph_copy');
  });
}
