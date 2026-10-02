import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/runs.dart';

import 'support.dart';

void main() {
  final mockup = Mockup();

  group('runs (ui-spec «Холст»)', () {
    test('are in the order they were created', () {
      final b = Journal('bbbb-run', node: 'collect', startedAt: 5);
      final a = Journal('aaaa-run', node: 'collect', startedAt: 5);
      final first = Journal('zzzz-run', node: 'collect', startedAt: 1);
      expect(
        [
          for (final r in runsInOrder(sessionOf([b, a, first]))) r.id,
        ],
        ['zzzz-run', 'aaaa-run', 'bbbb-run'],
      );
    });

    test('a run without step-started is not started', () {
      final run = Journal('wait-run', node: 'collect', startedAt: 0);
      expect(phaseOf(run.data), RunPhase.notStarted);
    });

    test('the switcher shows each run in its state, split ones with the word '
        'split', () {
      final chips = runChips(mockup.session, mockup.outcomes);
      expect(
        [for (final c in chips) (c.shortId, c.phase, c.word)],
        [
          ('k7f2', RunPhase.split, 'split'),
          ('c3d4', RunPhase.finished, null),
          ('e5f6', RunPhase.running, null),
        ],
      );
      final failed = Journal('fail-run', node: 'collect', startedAt: 0);
      failed.fail(
        failed.step('collect', 0, end: 1, exit: 1),
        1,
        'exited with code 1',
      );
      expect(phaseOf(failed.data), RunPhase.failed);
    });

    test('opening a session picks its first running run as it was at that '
        'moment', () {
      final ended = Journal('ende-run', node: 'collect', startedAt: 0);
      ended.step('collect', 0, end: 30);
      ended.finish(30);
      final failed = Journal('fail-run', node: 'collect', startedAt: 1);
      failed.fail(
        failed.step('collect', 1, end: 2, exit: 1),
        2,
        'exited with code 1',
      );
      final later = Journal('late-run', node: 'collect', startedAt: 40)
        ..step('collect', 40);
      final session = sessionOf([ended, failed, later]);
      expect(phaseAt(ended.data, at(10)), RunPhase.running);
      expect(phaseAt(ended.data, at(31)), RunPhase.finished);
      expect(openingRun(session, at(10))!.id, 'ende-run');
      expect(openingRun(session, at(35))!.id, 'fail-run');
      expect(openingRun(session, at(50))!.id, 'late-run');
      expect(openingRun(session, at(0)), isNull);
    });

    test('opening a session without running or failed runs picks the last', () {
      final first = Journal('firs-run', node: 'collect', startedAt: 0);
      first.step('collect', 0, end: 1);
      first.finish(1);
      final last = Journal('last-run', node: 'collect', startedAt: 2);
      last.step('collect', 2, end: 3);
      last.finish(3);
      expect(openingRun(sessionOf([last, first]), at(10))!.id, 'last-run');
    });

    test('a run whose log was read incompletely is marked', () {
      final run = Journal('odd0-run', node: 'collect', startedAt: 0);
      run.events.add(const UnknownEvent({'runId': 'odd0-run', 'event': 'x'}));
      expect(
        runChips(sessionOf([run]), outcomesOf(const {})).single.incomplete,
        isTrue,
      );
      expect(
        runChips(mockup.session, mockup.outcomes).first.incomplete,
        isFalse,
      );
      expect(logReadIncompletely, 'Log read incompletely');
    });

    test('a run whose fork outcome could not be read is marked Log read '
        'incompletely', () {
      final chips = runChips(
        mockup.session,
        outcomesOf(const {}, failed: {'verdict-outcome-1': 'gone.json: bad'}),
      );
      expect(chips.first.incomplete, isTrue);
      expect(chips.first.problems, [
        'the outcome in document verdict-outcome-1 cannot be read: '
            'gone.json: bad',
      ]);
      expect(chips.last.incomplete, isFalse);
    });

    test('the steps of a run are its ancestors\' steps from the root down to '
        'the split, then its own', () {
      final root = Journal('root-run', node: 'collect', startedAt: 0);
      root.step('collect', 0, end: 1);
      root.step('verdict', 1, end: 2);
      root.split(2);
      final middle = Journal(
        'midd-run',
        parent: 'root-run',
        node: 'publish',
        startedAt: 2,
      );
      middle.step('publish', 3, end: 4);
      middle.split(4);
      final leaf = Journal(
        'leaf-run',
        parent: 'midd-run',
        node: 'notify',
        startedAt: 4,
      );
      leaf.step('notify', 5);
      final steps = stepsOfRun(sessionOf([root, middle, leaf]), 'leaf-run');
      expect(
        [for (final s in steps) (s.node, s.run.id, s.inherited)],
        [
          ('collect', 'root-run', true),
          ('verdict', 'root-run', true),
          ('publish', 'midd-run', true),
          ('notify', 'leaf-run', false),
        ],
      );
    });

    test('a root run has only its own steps', () {
      final steps = stepsOfRun(mockup.session, 'k7f2-run');
      expect(steps, hasLength(7));
      expect(steps.every((s) => !s.inherited), isTrue);
    });
  });
}
