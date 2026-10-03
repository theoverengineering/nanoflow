import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/sessions.dart';

import 'support.dart';

void main() {
  /// 14:15:37, 12m 26s after [t0].
  final now = at(746);

  /// Session a1b2: collect finished, inspect running.
  Journal running() => Journal('a1b2-session')
    ..step('collect', 1, end: 149, output: 'change')
    ..step('inspect', 150);

  group('a session (ui-spec «Сессии»)', () {
    test('starts at its session-started', () {
      final session = Journal('a1b2-session', startedAt: 5)..resume(30);
      expect(summarize(session.data, now)!.startedAt, at(5));
    });

    test('without a last event is running: Running for 12m 26s', () {
      final summary = summarize(running().data, now)!;
      expect(summary.status, SessionStatus.running);
      expect(summary.statusText, 'Running for 12m 26s');
    });

    test('that ends with session-failed is failed: Failed in 6m 18s', () {
      final session = running()..fail(378, 'StateError: inspect failed');
      final summary = summarize(session.data, now)!;
      expect(summary.status, SessionStatus.failed);
      expect(summary.statusText, 'Failed in 6m 18s');
    });

    test('that ends with session-finished is finished: Finished in 3m 04s', () {
      final session = Journal('a1b2-session')
        ..step('collect', 1, end: 184)
        ..finish(184);
      final summary = summarize(session.data, now)!;
      expect(summary.status, SessionStatus.finished);
      expect(summary.statusText, 'Finished in 3m 04s');
    });

    test('that is running lasts until now', () {
      expect(
        summarize(running().data, now)!.duration,
        const Duration(minutes: 12, seconds: 26),
      );
      expect(
        summarize(running().data, at(800))!.duration,
        const Duration(seconds: 800),
      );
    });

    test('that is running with failed steps is marked 1 failed', () {
      final failed = running()..step('notify', 160, end: 161, failed: true);
      expect(summarize(failed.data, now)!.failedBadge, '1 failed');
      expect(summarize(running().data, now)!.failedBadge, isNull);
      expect(
        summarize((failed..fail(170, 'StateError')).data, now)!.failedBadge,
        isNull,
      );
    });

    test('a failed step that ran again and finished is not failed', () {
      final session = running()
        ..step('notify', 160, end: 161, failed: true)
        ..resume(200);
      session.events.add(
        StepStarted(time: at(201), stepId: session.steps.last.id),
      );
      session.events.add(
        StepFinished(
          time: at(202),
          stepId: session.steps.last.id,
          outputId: null,
        ),
      );
      expect(summarize(session.data, now)!.failedBadge, isNull);
    });

    test('counts its steps: 1 step, 2 steps', () {
      expect(summarize(running().data, now)!.stepsText, '2 steps');
      final one = Journal('a1b2-session')..step('collect', 1);
      expect(summarize(one.data, now)!.stepsText, '1 step');
    });

    test('shows the local day and time it started: Today · 14:03:11', () {
      expect(summarize(running().data, now)!.firstLine, 'Today · 14:03:11');
      expect(
        summarize(running().data, now.add(const Duration(days: 1)))!.firstLine,
        'Yesterday · 14:03:11',
      );
    });

    test('is named by its short id', () {
      expect(summarize(running().data, now)!.shortId, 'a1b2');
    });

    test('strip reads started 14:03:11 and running 12m 26s', () {
      final summary = summarize(running().data, now)!;
      expect(summary.startedText, 'started 14:03:11');
      expect(summary.stripStatus, 'running 12m 26s');
      expect(
        summarize(running().data, at(2 * 3600 + 54 * 60 + 27))!.stripStatus,
        'running 2h 54m 27s',
      );
    });

    test('without a session-started yet is not listed', () {
      final unread = Journal('unre-session', startedAt: null);
      expect(summarize(unread.data, now), isNull);
      expect(sessionSummaries([unread.data], now), isEmpty);
    });
  });

  test('a workflow without sessions says No sessions yet and where they '
      'come from', () {
    expect(noSessionsYet, 'No sessions yet');
    expect(
      noSessionsHint('/Users/me/Projects/review/nanoflow.graph.json'),
      'Sessions of the workflow appear as it runs: '
      'they are read from runs/ next to nanoflow.graph.json.',
    );
  });

  test('sessions are listed newest first', () {
    final older = Journal('olde-session', startedAt: -3600).data;
    final newer = Journal('newe-session').data;
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

  group('the sessions of a workflow', () {
    final review = Journal('revi-session').data;
    final release = Journal('rele-session', workflow: 'release').data;
    final gone = Journal('gone-session', workflow: 'renamed').data;
    final all = [review, release, gone];

    test('are those whose workflow the graph file names it by', () {
      final graph = reviewGraphFile();
      expect(sessionsOfWorkflow(all, graph, 'lib/review.dart#review'), [
        review,
      ]);
      expect(sessionsOfWorkflow(all, graph, 'lib/release.dart#release'), [
        release,
      ]);
    });

    test('without a workflow selected are none', () {
      expect(sessionsOfWorkflow(all, reviewGraphFile(), null), isEmpty);
    });

    test('are all sessions while no graph file has been read', () {
      expect(sessionsOfWorkflow(all, null, null), all);
    });

    test('of a workflow the graph file does not have are listed under its '
        'name', () {
      final later = Journal('renm-session', workflow: 'renamed').data;
      expect(
        sessionsOfWorkflow([...all, later], reviewGraphFile(), 'renamed'),
        [gone, later],
      );
    });
  });

  group('the workflows to choose from', () {
    final sessions = [
      Journal('revi-session').data,
      Journal('depl-session', workflow: 'deploy').data,
      Journal('dep2-session', workflow: 'deploy').data,
      Journal('back-session', workflow: 'backup').data,
    ];

    test('are those of the graph file in its order, then those sessions ran '
        'that it does not have, by name', () {
      final choices = workflowChoices(reviewGraphFile(), sessions);
      expect(
        [for (final w in choices) (w.id, w.name, w.inGraphFile)],
        [
          ('lib/review.dart#review', 'review', true),
          ('lib/release.dart#release', 'release', true),
          ('backup', 'backup', false),
          ('deploy', 'deploy', false),
        ],
      );
      expect(choices.first.function, reviewGraphFile().functions.values.first);
      expect(choices.last.function, isNull);
    });

    test('count the sessions of workflows the graph file does not have', () {
      expect(sessionsNotInGraph(reviewGraphFile(), sessions), {
        'backup': 1,
        'deploy': 2,
      });
      expect(sessionsNotInGraph(reviewGraphFile(), sessions.take(1)), isEmpty);
    });
  });
}
