import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/body_path.dart';
import 'package:nanoflow_ui/state/node_keys.dart';
import 'package:test/test.dart';

import '../layout/support.dart';

void main() {
  final release = loadGraphFile('release');
  const publishId = 'lib/publish.dart#publish';
  const releaseId = 'lib/release.dart#release';
  final moved = withEffectFirst(release, releaseId, 'plan');
  final movedInside = withEffectFirst(moved, publishId, 'upload');

  test('a node\'s key is what it is and how many alike stand before it, '
      'whatever its id', () {
    final body = release.functions[releaseId]!.body;
    expect(nodeKey(body, body.node('5')!), 'call $publishId 0');
    expect(nodeKey(body, body.node('1')!), 'effect plan 0');
    final shifted = moved.functions[releaseId]!.body;
    // The effect added first is another `plan`: the old one is the second.
    expect(nodeKey(shifted, shifted.node('2')!), 'effect plan 1');
    expect(nodeOfKey(shifted, 'call $publishId 0')!.id, '6');
    expect(nodeOfKey(shifted, 'effect nothing 0'), isNull);
  });

  test('a path opened follows its nodes into a graph file written again, '
      'as far as they are there', () {
    ({List<Opened> path, bool complete}) follow(
      List<Opened> path,
      GraphFile after,
    ) => followPath(
      path,
      before: release.functions[releaseId]!,
      beforeFunctions: release.functions,
      after: after.functions[releaseId]!,
      afterFunctions: after.functions,
    );

    const publish = Opened('5', functionId: publishId);
    void expectFollowed(
      ({List<Opened> path, bool complete}) actual,
      List<Opened> path, {
      required bool complete,
      String? reason,
    }) {
      expect(actual.path, path, reason: reason);
      expect(actual.complete, complete, reason: reason);
    }

    expectFollowed(follow(const [publish], moved), const [
      Opened('6', functionId: publishId),
    ], complete: true);
    expectFollowed(
      follow(const [publish, Opened('4')], movedInside),
      const [Opened('6', functionId: publishId)],
      complete: false,
      reason: 'rollback is no call: nothing opens under it',
    );
    expectFollowed(follow(const [], moved), const [], complete: true);

    final noPublish = release.toJson();
    final body =
        ((noPublish['functions']! as Map)[releaseId]! as Map)['body']! as Map;
    body['nodes'] = [
      for (final node in body['nodes']! as List)
        if ((node as Map)['id'] != '5') node,
    ];
    body['edges'] = [
      for (final edge in body['edges']! as List)
        if ((edge as Map)['from'] != '5' && edge['to'] != '5') edge,
    ];
    expectFollowed(
      follow(const [publish], GraphFile.fromJson(noPublish)),
      const [],
      complete: false,
    );
  });
}
