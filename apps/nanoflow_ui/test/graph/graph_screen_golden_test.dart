import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart' hide Route;
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

  testWidgets('a session without a snapshot: its notes under the session '
      'bar', (tester) async {
    await pumpGraphScreen(
      tester,
      model: ownedModel(
        file: releaseFile,
        changes: changesOf([
          Journal('r1r1-session', workflow: 'release', snapshot: false)
            ..step('plan', 1, end: 3)
            ..step('build', 3),
          Journal('d1d1-session', workflow: 'deploy', startedAt: -60),
        ]),
      ),
      now: () => at(200),
    );
    await expectGolden(tester, 'graph_session');
  });
}
