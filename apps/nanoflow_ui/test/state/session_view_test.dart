import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/session_feed.dart';
import 'package:nanoflow_ui/state/session_view.dart';

import 'support.dart';

void main() {
  final mockup = Mockup();
  final now = Mockup.now;
  final noOutcomes = outcomesOf(const {});

  group('a session (ui-spec «Сессии»)', () {
    test('starts at its first run-started', () {
      final late = Journal('late-run', node: 'collect', startedAt: 30)
        ..step('collect', 30);
      final early = Journal('earl-run', node: 'collect', startedAt: 5)
        ..step('collect', 5);
      expect(summarize(sessionOf([late, early]), now)!.startedAt, at(5));
    });

    test('with a run not ended is running: Running for 12m 26s', () {
      final summary = summarize(mockup.session, now)!;
      expect(summary.status, SessionStatus.running);
      expect(summary.statusText, 'Running for 12m 26s');
    });

    test('whose runs have all ended, one with run-failed, is failed: '
        'Failed in 6m 18s', () {
      final ok = Journal('okok-run', node: 'collect', startedAt: 0);
      ok.step('collect', 0, end: 10);
      ok.finish(10);
      final bad = Journal('badd-run', node: 'collect', startedAt: 0);
      bad.fail(
        bad.step('collect', 0, end: 378, exit: 1),
        378,
        'exited with code 1',
      );
      final summary = summarize(sessionOf([ok, bad]), now)!;
      expect(summary.status, SessionStatus.failed);
      expect(summary.statusText, 'Failed in 6m 18s');
    });

    test('whose runs have all ended without failures is finished: '
        'Finished in 3m 04s', () {
      final run = Journal('done-run', node: 'collect', startedAt: 0);
      run.step('collect', 0, end: 184);
      run.finish(184);
      final summary = summarize(sessionOf([run]), now)!;
      expect(summary.status, SessionStatus.finished);
      expect(summary.statusText, 'Finished in 3m 04s');
    });

    test('lasts from its first run-started to the end of its last run', () {
      final parent = Journal('pare-run', node: 'collect', startedAt: 0);
      parent.step('collect', 0, end: 10);
      parent.split(10);
      final longer = Journal(
        'long-run',
        parent: 'pare-run',
        node: 'publish',
        startedAt: 10,
      );
      longer.step('publish', 11, end: 200);
      longer.finish(200);
      final shorter = Journal(
        'shor-run',
        parent: 'pare-run',
        node: 'notify',
        startedAt: 10,
      );
      shorter.step('notify', 11, end: 20);
      shorter.finish(20);
      expect(
        summarize(sessionOf([parent, longer, shorter]), now)!.duration,
        const Duration(seconds: 200),
      );
    });

    test('that is running lasts until now', () {
      expect(
        summarize(mockup.session, now)!.duration,
        const Duration(minutes: 12, seconds: 26),
      );
      expect(
        summarize(mockup.session, at(800))!.duration,
        const Duration(seconds: 800),
      );
    });

    test('a run not started yet keeps the session running', () {
      final parent = Journal('pare-run', node: 'collect', startedAt: 0);
      parent.step('collect', 0, end: 10);
      parent.split(10);
      final child = Journal(
        'chil-run',
        parent: 'pare-run',
        node: 'notify',
        startedAt: 10,
      );
      expect(
        summarize(sessionOf([parent, child]), now)!.status,
        SessionStatus.running,
      );
    });

    test('that is running with failed runs is marked 1 failed', () {
      final failed = Journal('fail-run', node: 'collect', startedAt: 0);
      failed.fail(
        failed.step('collect', 0, end: 5, exit: 2),
        5,
        'exited with code 2',
      );
      final running = Journal('runn-run', node: 'collect', startedAt: 1)
        ..step('collect', 1);
      expect(
        summarize(sessionOf([failed, running]), now)!.failedBadge,
        '1 failed',
      );
      expect(summarize(mockup.session, now)!.failedBadge, isNull);
      expect(summarize(sessionOf([failed]), now)!.failedBadge, isNull);
    });

    test('counts its runs: 1 run, 3 runs', () {
      expect(summarize(mockup.session, now)!.runsText, '3 runs');
      expect(summarize(sessionOf([mockup.k7f2]), now)!.runsText, '1 run');
    });

    test('shows the local day and time it started: Today · 14:03:11', () {
      expect(summarize(mockup.session, now)!.firstLine, 'Today · 14:03:11');
      expect(
        summarize(mockup.session, now.add(const Duration(days: 1)))!.firstLine,
        'Yesterday · 14:03:11',
      );
    });

    test('is named by its short id', () {
      expect(summarize(mockup.session, now)!.shortId, 'a1b2');
    });

    test('strip reads started 14:03:11 and running 12m 26s', () {
      final summary = summarize(mockup.session, now)!;
      expect(summary.startedText, 'started 14:03:11');
      expect(summary.stripStatus, 'running 12m 26s');
      expect(
        summarize(mockup.session, at(2 * 3600 + 54 * 60 + 27))!.stripStatus,
        'running 2h 54m 27s',
      );
    });

    test('without a run-started yet is not listed', () {
      final unread = Journal('unre-run', node: 'collect', startedAt: null);
      expect(summarize(sessionOf([unread]), now), isNull);
      expect(
        sessionSummaries([
          sessionOf([unread]),
        ], now),
        isEmpty,
      );
    });

    test('a graph without sessions says No runs yet and how to start one', () {
      expect(noRunsYet, 'No runs yet');
      expect(
        noRunsHint('/Users/me/Projects/review/review.yaml'),
        'Start a session from the graph\'s directory: '
        'nanoflow run -- nanoflow-yaml review.yaml',
      );
    });

    test('sessions are listed newest first', () {
      final older = sessionOf([
        Journal('olde-run', node: 'collect', startedAt: -3600),
      ], id: 'olde-session');
      final newer = sessionOf([
        Journal('newe-run', node: 'collect', startedAt: 0),
      ], id: 'newe-session');
      expect(
        [
          for (final s in sessionSummaries([older, newer], now)) s.id,
        ],
        ['newe-session', 'olde-session'],
      );
      expect(
        [
          for (final s in sessionsNewestFirst([older, newer])) s.id,
        ],
        ['newe-session', 'olde-session'],
      );
    });
  });

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
      final chips = runChips(mockup.session);
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

    test('a run whose log was read incompletely is marked', () {
      final run = Journal('odd0-run', node: 'collect', startedAt: 0);
      run.events.add(const UnknownEvent({'runId': 'odd0-run', 'event': 'x'}));
      expect(runChips(sessionOf([run])).single.incomplete, isTrue);
      expect(runChips(mockup.session).first.incomplete, isFalse);
      expect(logRunIncompletely, 'Log read incompletely');
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

  group('logs (ui-spec «Logs»)', () {
    List<StepRow> stepRows(String runId, {DateTime? at}) => [
      for (final row in logRows(
        mockup.session,
        runId,
        outcomes: mockup.outcomes,
        now: at ?? now,
      ))
        if (row is StepRow) row,
    ];

    test('the header names the run and its steps: run e5f6 · 8 steps, 7 '
        'inherited from k7f2', () {
      expect(
        logsHeader(mockup.session, 'e5f6-run').text,
        'run e5f6 · 8 steps, 7 inherited from k7f2',
      );
      expect(
        logsHeader(mockup.session, 'e5f6-run').stepsText,
        '8 steps, 7 inherited from k7f2',
      );
    });

    test('a root run\'s header has no inherited part', () {
      expect(logsHeader(mockup.session, 'k7f2-run').text, 'run k7f2 · 7 steps');
      final one = Journal('oone-run', node: 'collect', startedAt: 0)
        ..step('collect', 0);
      expect(
        logsHeader(sessionOf([one]), 'oone-run').text,
        'run oone · 1 step',
      );
    });

    test('a row is the node, its first start, and how long it took', () {
      final rows = stepRows('e5f6-run');
      expect(
        [for (final r in rows) (r.name, r.started, r.took)],
        [
          ('collect', '14:03:11', '2m 29s'),
          ('is-empty', '14:05:40', '1s'),
          ('inspect', '14:05:41', '3m 12s'),
          ('verdict', '14:08:53', '0.4s'),
          ('fix', '14:08:54', '26s'),
          ('inspect', '14:09:20', '4m 02s'),
          ('verdict', '14:13:22', '0.3s'),
          ('notify', '14:13:23', '2m 14s'),
        ],
      );
    });

    test('a fork row adds the outcome and where it went: returned → fix', () {
      expect(
        [for (final r in stepRows('e5f6-run')) r.detail],
        [
          null,
          'else → inspect',
          null,
          'returned → fix',
          null,
          null,
          'accepted → publish, notify',
          null,
        ],
      );
    });

    test('a fork row whose outcome is not read yet has no detail', () {
      final rows = logRows(
        mockup.session,
        'k7f2-run',
        outcomes: noOutcomes,
        now: now,
      );
      expect(rows.whereType<StepRow>().every((r) => r.detail == null), isTrue);
    });

    test('a fork row whose outcome leads nowhere says end', () {
      const graph = <String, Object?>{
        'start': 'check',
        'nodes': {
          'check': {'decide': 'c', 'then': 'stop'},
          'stop': {
            'decide': 's',
            'then': {'skip': <String>[]},
          },
        },
      };
      final run = Journal('ends-run', node: 'check', startedAt: 0);
      run.step('check', 0, end: 1, output: 'false-doc');
      run.finish(1);
      final other = Journal('stub-run', node: 'stop', startedAt: 0);
      other.step('stop', 0, end: 1, output: 'skip-doc');
      other.finish(1);
      final session = sessionOf([run, other], graph: graph);
      final outcomes = outcomesOf({'false-doc': false, 'skip-doc': 'skip'});
      String? detail(String runId) => logRows(
        session,
        runId,
        outcomes: outcomes,
        now: now,
      ).whereType<StepRow>().single.detail;
      expect(detail('ends-run'), 'false → end');
      expect(detail('stub-run'), 'skip → end');
    });

    test('a failed step\'s row shows the error of run-failed', () {
      final run = Journal('fail-run', node: 'verdict', startedAt: 0);
      run.fail(
        run.step('verdict', 0, end: 1, output: 'odd-doc'),
        1,
        'no target for outcome "odd"',
      );
      final row = logRows(
        sessionOf([run]),
        'fail-run',
        outcomes: outcomesOf({'odd-doc': 'odd'}),
        now: now,
      ).whereType<StepRow>().single;
      expect(row.status, StepStatus.failed);
      expect(row.detail, 'no target for outcome "odd"');
      expect(row.failure, isTrue);
    });

    test('a step failed without step-finished took until run-failed', () {
      final run = Journal('fail-run', node: 'collect', startedAt: 0);
      run.fail(
        run.step('collect', 0),
        3,
        'cannot start the graph program: gone',
      );
      final row = logRows(
        sessionOf([run]),
        'fail-run',
        outcomes: noOutcomes,
        now: now,
      ).whereType<StepRow>().single;
      expect(row.took, '3s');
      expect(row.barEnd, 1.0);
    });

    test('a running step ticks until now and is striped', () {
      final notify = stepRows('e5f6-run').last;
      expect(notify.status, StepStatus.running);
      expect(notify.striped, isTrue);
      expect(stepRows('e5f6-run', at: at(747)).last.took, '2m 15s');
      expect(stepRows('e5f6-run').first.striped, isFalse);
    });

    test('a restarted step is marked 2 starts', () {
      expect(
        [for (final r in stepRows('e5f6-run')) r.startsText],
        [null, null, null, null, null, '2 starts', null, null],
      );
    });

    test('inherited rows are flagged', () {
      expect(
        [for (final r in stepRows('e5f6-run')) r.inherited],
        [true, true, true, true, true, true, true, false],
      );
    });

    test('a split separator stands between the parent\'s last step and the '
        'child\'s first: split · run e5f6', () {
      final rows = logRows(
        mockup.session,
        'e5f6-run',
        outcomes: mockup.outcomes,
        now: now,
      );
      expect(rows, hasLength(9));
      final split = rows[7] as SplitRow;
      expect(split.text, 'split · run e5f6');
      expect((rows[6] as StepRow).name, 'verdict');
      expect((rows[8] as StepRow).name, 'notify');
    });

    test('an ended run ends with its state: finished, failed with the error, '
        'split with its children', () {
      EndRow end(SessionData session, String runId) =>
          logRows(session, runId, outcomes: noOutcomes, now: now).last
              as EndRow;
      expect(end(mockup.session, 'c3d4-run').text, 'Run finished');
      final split = end(mockup.session, 'k7f2-run');
      expect(split.text, 'Run split into');
      expect(split.children, ['c3d4-run', 'e5f6-run']);
      final failed = Journal('fail-run', node: 'collect', startedAt: 0);
      failed.fail(
        failed.step('collect', 0, end: 1, exit: 1),
        1,
        'exited with code 1',
      );
      expect(
        end(sessionOf([failed]), 'fail-run').text,
        'Run failed: exited with code 1',
      );
      expect(
        logRows(
          mockup.session,
          'e5f6-run',
          outcomes: noOutcomes,
          now: now,
        ).last,
        isA<StepRow>(),
      );
    });

    test('a row\'s bar sits on the time scale of the session', () {
      final rows = stepRows('e5f6-run');
      expect(rows.first.barStart, 0);
      expect(rows.first.barEnd, closeTo(149 / 746, 1e-9));
      expect(rows.last.barStart, closeTo(612 / 746, 1e-9));
      expect(rows.last.barEnd, 1);
    });

    test('the time scale runs from the session\'s start to its end, or to '
        'now while it runs', () {
      final running = timeScale(mockup.session, now);
      expect((running.start, running.end), (at(0), now));
      final run = Journal('done-run', node: 'collect', startedAt: 0);
      run.step('collect', 0, end: 184);
      run.finish(184);
      final ended = timeScale(sessionOf([run]), now);
      expect((ended.start, ended.end), (at(0), at(184)));
      expect(ended.fraction(at(92)), 0.5);
    });
  });

  group('the whole view', () {
    test('puts together what the session shows', () {
      final view = SessionView.of(
        mockup.session,
        now: now,
        outcomes: mockup.outcomes,
        runId: 'e5f6-run',
        stepId: 'k7f2-fix-4',
      );
      expect(view.summary!.statusText, 'Running for 12m 26s');
      expect(view.graph!.nodes.keys, contains('notify'));
      expect(view.runs, hasLength(3));
      expect(view.marks.stateOf('notify'), NodeState.running);
      expect(
        view.run!.header.text,
        'run e5f6 · 8 steps, 7 inherited from k7f2',
      );
      expect(view.run!.rows, hasLength(9));
      expect(view.run!.path.inputs, contains('notify'));
      expect(view.selectedNode, 'fix');
    });

    test('without a selected run shows no logs', () {
      final view = SessionView.of(
        mockup.session,
        now: now,
        outcomes: noOutcomes,
      );
      expect(view.run, isNull);
      expect(view.selectedNode, isNull);
    });
  });
}
