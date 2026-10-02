import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/state/graph_marks.dart';
import 'package:nanoflow_ui/state/runs.dart';

import 'support.dart';

void main() {
  final mockup = Mockup();
  final noOutcomes = outcomesOf(const {});

  group('the graph (ui-spec «Граф»)', () {
    test('a node a run failed on is failed, whatever else is on it', () {
      final failed = Journal('fail-run', node: 'collect', startedAt: 0);
      failed.fail(
        failed.step('collect', 0, end: 1, exit: 1),
        1,
        'exited with code 1',
      );
      final running = Journal('runn-run', node: 'collect', startedAt: 0)
        ..step('collect', 2);
      final done = Journal('done-run', node: 'collect', startedAt: 0)
        ..step('collect', 0, end: 1);
      final marks = GraphMarks.of(
        sessionOf([done, running, failed]),
        noOutcomes,
      );
      expect(marks.stateOf('collect'), NodeState.failed);
    });

    test('a node with a step without step-finished is running', () {
      final marks = GraphMarks.of(mockup.session, mockup.outcomes);
      expect(marks.stateOf('notify'), NodeState.running);
      final done = Journal('done-run', node: 'collect', startedAt: 0)
        ..step('collect', 0, end: 1);
      final running = Journal('runn-run', node: 'collect', startedAt: 0)
        ..step('collect', 2);
      expect(
        GraphMarks.of(
          sessionOf([done, running]),
          noOutcomes,
        ).stateOf('collect'),
        NodeState.running,
      );
    });

    test('a node with finished steps is visited', () {
      final marks = GraphMarks.of(mockup.session, mockup.outcomes);
      for (final node in [
        'collect',
        'is-empty',
        'inspect',
        'verdict',
        'fix',
        'publish',
      ]) {
        expect(marks.stateOf(node), NodeState.visited, reason: node);
      }
    });

    test('a node without steps is not visited', () {
      final marks = GraphMarks.of(mockup.session, mockup.outcomes);
      expect(marks.stateOf('discard'), NodeState.notVisited);
    });

    test('each run is marked on the node of its last step, in its state; '
        'a split run is not marked', () {
      final marks = GraphMarks.of(mockup.session, mockup.outcomes);
      expect(
        [for (final m in marks.markersOn('publish')) (m.shortId, m.phase)],
        [('c3d4', RunPhase.finished)],
      );
      expect(
        [for (final m in marks.markersOn('notify')) (m.shortId, m.phase)],
        [('e5f6', RunPhase.running)],
      );
      expect(marks.markersOn('verdict'), isEmpty);
    });

    test('a run not started is marked on its start node', () {
      final parent = Journal('pare-run', node: 'collect', startedAt: 0);
      parent.step('collect', 0, end: 1);
      parent.split(1);
      final child = Journal(
        'chil-run',
        parent: 'pare-run',
        node: 'notify',
        startedAt: 1,
      );
      final marks = GraphMarks.of(sessionOf([parent, child]), noOutcomes);
      expect(
        [for (final m in marks.markersOn('notify')) (m.shortId, m.phase)],
        [('chil', RunPhase.notStarted)],
      );
    });

    test('a node entered more than once shows its visits: 2×', () {
      final marks = GraphMarks.of(mockup.session, mockup.outcomes);
      expect(marks.visitText('inspect'), '2×');
      expect(marks.visitText('verdict'), '2×');
      expect(marks.visitText('collect'), isNull);
      expect(marks.visitText('discard'), isNull);
    });

    test(
      'arrows count how often runs of the session went through each exit',
      () {
        final marks = GraphMarks.of(mockup.session, mockup.outcomes);
        expect(
          {
            for (final MapEntry(:key, :value) in marks.passes.entries)
              '${key.node}#${key.exit}': value,
          },
          {
            'collect#0': 1,
            'is-empty#1': 1,
            'inspect#0': 2,
            'verdict#1': 1,
            'fix#0': 1,
            'verdict#0': 1,
          },
        );
        expect(marks.counterOf('inspect', 0), '2×');
      },
    );

    test('a fork step passes the exit its outcome chooses', () {
      final run = Journal('fork-run', node: 'is-empty', startedAt: 0);
      run.step('is-empty', 0, end: 1, output: 'true-doc');
      run.step('is-empty', 2, end: 3, output: 'false-doc');
      run.step('is-empty', 4, end: 5, output: 'string-doc');
      final marks = GraphMarks.of(
        sessionOf([run]),
        outcomesOf({
          'true-doc': true,
          'false-doc': false,
          'string-doc': 'true',
        }),
      );
      expect(marks.passesOf('is-empty', 0), 1);
      expect(marks.passesOf('is-empty', 1), 2);
    });

    test('a fork step whose outcome is not read yet passes nothing, and its '
        'document is needed', () {
      final marks = GraphMarks.of(mockup.session, noOutcomes);
      expect(marks.passesOf('verdict', 0), 0);
      expect(marks.passesOf('verdict', 1), 0);
      expect(marks.passesOf('collect', 0), 1);
      expect(forkOutputs(mockup.session), {
        'is-empty-outcome',
        'verdict-outcome-1',
        'verdict-outcome-2',
      });
    });

    test('a list target counts once per split', () {
      final marks = GraphMarks.of(mockup.session, mockup.outcomes);
      expect(marks.passesOf('verdict', 0), 1);
    });

    test('an empty target counts when chosen', () {
      const graph = <String, Object?>{
        'start': 'work',
        'nodes': {
          'work': {'command': 'w', 'then': 'route'},
          'route': {
            'decide': 'r',
            'then': {'skip': <String>[], 'go': 'work'},
            'else': <String>[],
          },
          'last': {'command': 'l', 'then': <String>[]},
        },
      };
      final run = Journal('stub-run', node: 'work', startedAt: 0);
      run.step('route', 0, end: 1, output: 'skip-doc');
      run.step('route', 1, end: 2, output: 'other-doc');
      run.step('last', 2, end: 3);
      run.finish(3);
      final marks = GraphMarks.of(
        sessionOf([run], graph: graph),
        outcomesOf({'skip-doc': 'skip', 'other-doc': 'other'}),
      );
      expect(marks.passesOf('route', 0), 1);
      expect(marks.passesOf('route', 2), 1);
      expect(marks.passesOf('last', 0), 1);
    });

    test('a step its run failed on passes nothing', () {
      final worker = Journal('work-run', node: 'collect', startedAt: 0);
      worker.fail(
        worker.step('collect', 0, end: 1, exit: 1),
        1,
        'exited with code 1',
      );
      final fork = Journal('fork-run', node: 'verdict', startedAt: 0);
      fork.fail(
        fork.step('verdict', 0, end: 1, output: 'odd-doc'),
        1,
        'no target for outcome "odd"',
      );
      final marks = GraphMarks.of(
        sessionOf([worker, fork]),
        outcomesOf({'odd-doc': 'odd'}),
      );
      expect(marks.passes, isEmpty);
    });

    test('a running step passes nothing yet', () {
      final run = Journal('runn-run', node: 'collect', startedAt: 0)
        ..step('collect', 0);
      expect(GraphMarks.of(sessionOf([run]), noOutcomes).passes, isEmpty);
    });

    test('an exit no run went through is untaken', () {
      final marks = GraphMarks.of(mockup.session, mockup.outcomes);
      expect(marks.isTaken('is-empty', 0), isFalse);
      expect(marks.counterOf('is-empty', 0), isNull);
      expect(marks.isTaken('is-empty', 1), isTrue);
    });

    test('the selected run\'s path is the exits its steps took, inherited ones '
        'too, and the nodes they entered', () {
      final path = pathOf(mockup.session, 'e5f6-run', mockup.outcomes);
      expect(path.exits, {
        (node: 'collect', exit: 0),
        (node: 'is-empty', exit: 1),
        (node: 'inspect', exit: 0),
        (node: 'verdict', exit: 1),
        (node: 'fix', exit: 0),
        (node: 'verdict', exit: 0),
      });
      expect(path.arrows, {
        (from: 'collect', exit: 0, to: 'is-empty'),
        (from: 'is-empty', exit: 1, to: 'inspect'),
        (from: 'inspect', exit: 0, to: 'verdict'),
        (from: 'verdict', exit: 1, to: 'fix'),
        (from: 'fix', exit: 0, to: 'inspect'),
        (from: 'verdict', exit: 0, to: 'notify'),
      });
      expect(path.inputs, {'is-empty', 'inspect', 'verdict', 'fix', 'notify'});
    });

    test('a run not started yet has its path into its start node', () {
      final parent = Journal('pare-run', node: 'verdict', startedAt: 0);
      parent.step('verdict', 0, end: 1, output: 'accepted-doc');
      parent.split(1);
      final child = Journal(
        'chil-run',
        parent: 'pare-run',
        node: 'notify',
        startedAt: 1,
      );
      final path = pathOf(
        sessionOf([parent, child]),
        'chil-run',
        outcomesOf({'accepted-doc': 'accepted'}),
      );
      expect(path.arrows, {(from: 'verdict', exit: 0, to: 'notify')});
      expect(path.inputs, {'notify'});
    });
  });
}
