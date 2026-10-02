import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/state/sessions.dart';

import 'support.dart';

void main() {
  final mockup = Mockup();
  final now = Mockup.now;

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
}
