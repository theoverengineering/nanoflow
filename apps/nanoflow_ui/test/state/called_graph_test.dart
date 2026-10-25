import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/state/called_graph.dart';

import '../layout/support.dart' show loadGraphFile;
import 'support.dart';

void main() {
  // chain calls carry from implement, and task's body is one call of it.
  final chain = loadGraphFile('chain');
  final carry = chain.functions['lib/task_graph.dart#carry']!;
  final task = chain.functions['lib/task_graph.dart#task']!;

  /// A session of chain on its graph: its own effects, then status in admit
  /// and coder in work, both called from carry.
  Journal chainSession() =>
      Journal('c1c1-session', workflow: 'chain', graph: chain.toJson())
        ..effect('workspace', 1, end: 2, place: 'lib/chain.dart:36')
        ..effect('status', 3, end: 4, place: 'lib/task_graph.dart:66')
        ..effect('coder', 4, end: 5, place: 'lib/task_graph.dart:139')
        ..effect('next task', 5, end: 6, place: 'lib/chain.dart:570');

  group('a session of its own', () {
    test('ran a workflow of the graph file as its workflow, by its name', () {
      final session = Journal('t1t1-session', workflow: 'task').data;
      expect(ranAsWorkflow(session, chain, task), isTrue);
      expect(ranAsWorkflow(chainSession().data, chain, task), isFalse);
    });

    test('ran a function the file has as no workflow under its name', () {
      final session = Journal('k1k1-session', workflow: 'carry').data;
      expect(ranAsWorkflow(session, chain, carry), isTrue);
      expect(ranAsWorkflow(chainSession().data, chain, carry), isFalse);
    });
  });

  group('a parent\'s session', () {
    test('found on its graph by the places of its own workflow', () {
      final session = chainSession().data;
      final places = placesOfSession(session, chain);
      expect(
        places.isWorkflow(chain.functions['lib/chain.dart#chain']!.body),
        isTrue,
      );
      expect(places.isCalled(carry.body), isTrue);
      expect(placesOfSession(session, null).nodes, isEmpty);
    });

    test('ran the function when an effect of it is in its body, or in what '
        'it calls', () {
      final session = chainSession().data;
      final places = placesOfSession(session, chain);
      expect(ranIn(session, places, carry.id), isTrue);
      expect(ranIn(session, places, 'lib/task_graph.dart#decide'), isFalse);
      final outside = Journal('c2c2-session', workflow: 'chain')
        ..effect('workspace', 1, end: 2, place: 'lib/chain.dart:36');
      expect(ranIn(outside.data, places, carry.id), isFalse);
    });

    test('has those of its effects in the function, in their order', () {
      final session = chainSession().data;
      final places = placesOfSession(session, chain);
      expect(
        [
          for (final effect in effectsIn(
            session,
            session.state.effects,
            places,
            carry.id,
          ))
            effect.effectId,
        ],
        ['c1c1-status-1', 'c1c1-coder-2'],
      );
    });
  });
}
