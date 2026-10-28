import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/freshness.dart' show CodeCheck;
import 'package:nanoflow_ui/state/session_feed.dart' show SessionData;
import 'package:nanoflow_ui/state/sessions.dart';

import 'support.dart';

void main() {
  /// 14:15:37, 12m 26s after [t0].
  final now = at(746);

  /// Session a1b2: collect finished, inspect running.
  Journal running() => Journal('a1b2-session')
    ..effect('collect', 1, end: 149, output: 'change')
    ..effect('inspect', 150);

  group('a session (ui-spec «Сессии»)', () {
    test('notes the code it ran on when that is not the code of its graph, '
        'or was not recorded (spec §9 «Сессия»)', () {
      final session = running().data;
      expect(summarize(session, now)!.codeNote, isNull);
      expect(
        summarize(session, now, code: CodeCheck.matches)!.codeNote,
        isNull,
      );
      expect(
        summarize(session, now, code: CodeCheck.otherCode)!.codeNote,
        'other code',
      );
      expect(
        summarize(session, now, code: CodeCheck.notChecked)!.codeNote,
        'not checked',
      );
      expect(
        sessionSummaries(
          [session],
          now,
          codeOf: (_) => CodeCheck.otherCode,
        ).single.codeNote,
        'other code',
      );
    });

    test('resumed on code other than the code it started on is marked '
        'resumed on changed code (decision 7)', () {
      expect(summarize(running().data, now)!.resumedNote, isNull);
      final sameCode = running()..resume(200);
      expect(summarize(sameCode.data, now)!.resumedNote, isNull);
      final changed = running()
        ..resume(200, code: 'sha256:edited', graphId: 'snapshot')
        ..resume(300);
      expect(summarize(changed.data, now)!.resumedNote, resumedOnChangedCode);
      expect(resumedOnChangedCode, 'resumed on changed code');
      // A code not recorded tells nothing.
      final unknown = running()..resume(200, code: null);
      expect(summarize(unknown.data, now)!.resumedNote, isNull);
      final startedUnknown = Journal('b2c3-session', code: null)
        ..resume(200, code: 'sha256:edited');
      expect(summarize(startedUnknown.data, now)!.resumedNote, isNull);
    });

    test('whose journal was read incompletely is marked Log read '
        'incompletely, why in its first five problems (ui-spec «Когда '
        'что-то не так»)', () {
      final journal = running();
      SessionData withProblems(int count) => SessionData(
        journal.session,
        events: journal.events,
        effects: journal.effects,
        problems: [
          for (var line = 1; line <= count; line++)
            'line $line is not an event: {',
        ],
      );

      final complete = summarize(journal.data, now)!;
      expect(complete.incomplete, isFalse);
      expect(complete.incompleteWhy, isNull);

      final one = summarize(withProblems(1), now)!;
      expect(one.incomplete, isTrue);
      expect(logReadIncompletely, 'Log read incompletely');
      expect(one.incompleteWhy, '''
Log read incompletely
line 1 is not an event: {''');

      expect(summarize(withProblems(7), now)!.incompleteWhy, '''
Log read incompletely
line 1 is not an event: {
line 2 is not an event: {
line 3 is not an event: {
line 4 is not an event: {
line 5 is not an event: {
and 2 more''');
    });

    test('of a workflow that calls the called graph opened says from which '
        '(open-as-graph design §4)', () {
      final session = running().data;
      expect(summarize(session, now)!.fromText, isNull);
      expect(summarize(session, now, from: 'chain')!.fromText, 'from chain');
      expect(
        sessionSummaries(
          [session],
          now,
          fromOf: (s) => s.session.workflow,
        ).single.fromText,
        'from review',
      );
    });

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
        ..effect('collect', 1, end: 184)
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

    group(
      'whose process is gone though its journal has not ended (owner spec §6)',
      () {
        test('is interrupted: Interrupted after the time to its last event, '
            'why in a tooltip', () {
          final summary = summarize((running()..processGone()).data, now)!;
          expect(summary.interrupted, isTrue);
          expect(summary.status, SessionStatus.running);
          expect(summary.duration, const Duration(seconds: 150));
          expect(summary.statusText, 'Interrupted after 2m 30s');
          expect(summary.stripStatus, 'interrupted after 2m 30s');
          expect(summary.statusWhy, interruptedWhy);
          expect(
            interruptedWhy,
            'The process that ran this session is gone; resume it to finish.',
          );
        });

        test('stops counting its time', () {
          final session = (running()..processGone()).data;
          expect(
            summarize(session, at(2000))!.duration,
            summarize(session, now)!.duration,
          );
          expect(
            summarize(session, at(2000))!.stripStatus,
            'interrupted after 2m 30s',
          );
        });

        test('that has ended is not interrupted', () {
          final finished = running()
            ..finish(184)
            ..processGone();
          final summary = summarize(finished.data, now)!;
          expect(summary.interrupted, isFalse);
          expect(summary.statusText, 'Finished in 3m 04s');
          expect(summary.statusWhy, isNull);
        });
      },
    );

    test('runs as before while its process runs, is not known to, or '
        'nothing has been told of it', () {
      for (final journal in [
        running(),
        running()..owned(testOwner, alive: true),
        running()..owned(testOwner, alive: null),
        running()..owned(null, alive: null),
      ]) {
        final summary = summarize(journal.data, now)!;
        expect(summary.interrupted, isFalse);
        expect(summary.statusText, 'Running for 12m 26s');
        expect(summary.stripStatus, 'running 12m 26s');
        expect(summary.statusWhy, isNull);
      }
    });

    test('that is running with failed effects is marked 1 failed', () {
      final failed = running()..effect('notify', 160, end: 161, failed: true);
      expect(summarize(failed.data, now)!.failedBadge, '1 failed');
      expect(summarize(running().data, now)!.failedBadge, isNull);
      expect(
        summarize((failed..fail(170, 'StateError')).data, now)!.failedBadge,
        isNull,
      );
    });

    test('a failed effect that ran again and finished is not failed', () {
      final session = running()
        ..effect('notify', 160, end: 161, failed: true)
        ..resume(200);
      session.events.add(
        EffectStarted(time: at(201), effectId: session.effects.last.id),
      );
      session.events.add(
        EffectFinished(
          time: at(202),
          effectId: session.effects.last.id,
          outputId: null,
        ),
      );
      expect(summarize(session.data, now)!.failedBadge, isNull);
    });

    test('counts its effects: 1 effect, 2 effects', () {
      expect(summarize(running().data, now)!.effectsText, '2 effects');
      final one = Journal('a1b2-session')..effect('collect', 1);
      expect(summarize(one.data, now)!.effectsText, '1 effect');
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
    expect(
      noSessionsHint(
        '/Users/me/Projects/ideaforge/nanoflow.graph.json',
        watching: 'ideas.db',
      ),
      'Sessions of the workflow appear as it runs: '
      'they are read from ideas.db.',
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

    test('have a called graph opened first, marked so; a workflow opened as '
        'one stays where it is', () {
      final graph = GraphFile.fromJson({
        ...graphFileJson(),
        'workflows': ['lib/review.dart#review'],
      });
      final choices = workflowChoices(
        graph,
        sessions.take(1),
        called: 'lib/release.dart#release',
      );
      expect(
        [for (final w in choices) (w.id, w.name, w.called, w.inGraphFile)],
        [
          ('lib/release.dart#release', 'release', true, true),
          ('lib/review.dart#review', 'review', false, true),
        ],
      );
      expect(
        [
          for (final w in workflowChoices(
            reviewGraphFile(),
            sessions.take(1),
            called: 'lib/release.dart#release',
          ))
            (w.name, w.called),
        ],
        [('review', false), ('release', false)],
      );
      expect(
        workflowChoices(graph, sessions.take(1), called: 'lib/gone.dart#gone'),
        hasLength(1),
      );
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
