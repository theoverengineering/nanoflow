import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/log_rows.dart';
import 'package:nanoflow_ui/state/session_feed.dart';

import 'support.dart';

void main() {
  final mockup = Mockup();
  final now = Mockup.now;
  final noOutcomes = outcomesOf(const {});

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
}
