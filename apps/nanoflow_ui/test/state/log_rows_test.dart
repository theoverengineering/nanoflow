import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/effect_places.dart';
import 'package:nanoflow_ui/state/log_rows.dart';
import 'package:nanoflow_ui/state/session_feed.dart';
import 'package:nanoflow_ui/state/texts.dart' show clockTime;
import 'package:nanoflow_ui/state/visits.dart' show StartOutcome;

import 'support.dart';

void main() {
  final file = copiesGraphFile();
  final places = EffectPlaces.of(
    file.functions['lib/copies.dart#inPlace'],
    file.functions,
  );
  final now = at(746);

  /// review's effects as docs/design/graph.png has them, at [places] of
  /// inPlace: collect and inspect done, inspect again, then notify running.
  Journal mockupJournal() => Journal('a1b2-session', workflow: 'inPlace')
    ..effect('collect', 0, end: 149, place: copiesAt(4))
    ..effect('inspect', 149, end: 341, place: copiesAt(7))
    ..effect('inspect', 341, end: 612, place: copiesAt(7), restarts: [400])
    ..effect('notify', 612, place: copiesAt(8));

  SessionData mockup() => mockupJournal().data;

  List<EffectRow> effectRows(
    SessionData session, {
    String? Function(String effectId)? copyOf,
    DateTime? time,
  }) => [
    for (final row in logRows(
      session,
      effects: session.state.effects,
      places: places,
      copyOf: copyOf,
      now: time ?? now,
    ))
      if (row is EffectRow) row,
  ];

  group('the header (ui-spec «Logs»)', () {
    test('counts the effects shown', () {
      expect(const LogsHeader(8).text, '8 effects');
      expect(const LogsHeader(1).text, '1 effect');
    });

    test('names the copy shown', () {
      expect(const LogsHeader(3, copy: 'copy 2').text, 'copy 2 · 3 effects');
    });
  });

  test('a row is the effect, its first start, and how long it took, in the '
      'order of first effect-started', () {
    final rows = effectRows(mockup());
    expect(
      [for (final row in rows) row.name],
      ['collect', 'inspect', 'inspect', 'notify'],
    );
    final first = rows.first;
    expect(first.started, '14:03:11');
    expect(first.took, '2m 29s');
    expect(first.status, StartOutcome.finished);
    expect(first.detail, isNull);
    expect(first.startsText, isNull);
  });

  test('a restarted effect is marked 2 starts', () {
    expect(effectRows(mockup())[2].startsText, '2 starts');
  });

  test('a running effect ticks until now and is striped', () {
    final last = effectRows(mockup()).last;
    expect(last.duration, const Duration(seconds: 746 - 612));
    expect(last.striped, isTrue);
  });

  group('a session whose process is gone (owner spec §6)', () {
    /// [mockupJournal], tag run beside notify until 700 s, then the process
    /// gone.
    SessionData interrupted() =>
        (mockupJournal()
              ..effect('tag', 620, end: 700, place: copiesAt(9), after: null)
              ..processGone())
            .data;

    test('its running effect is interrupted: when it would have ended is not '
        'known, so it took — ; its bar, not striped, runs to the end of the '
        'scale, whenever it is now', () {
      for (final time in [now, at(2000)]) {
        final rows = effectRows(interrupted(), time: time);
        final notify = rows[3];
        expect(notify.name, 'notify');
        expect(notify.status, StartOutcome.interrupted);
        expect(notify.striped, isFalse);
        expect(notify.duration, isNull);
        expect(notify.took, '—');
        expect(notify.barStart, closeTo(612 / 700, 1e-9));
        expect(notify.barEnd, 1);
        expect(rows.last.status, StartOutcome.finished);
        expect(rows.last.took, '1m 20s');
      }
    });

    test('killed in the middle of an effect, the start of which is the last '
        'event of the journal: no 0.0s', () {
      final row = effectRows((mockupJournal()..processGone()).data).last;
      expect(row.name, 'notify');
      expect(row.status, StartOutcome.interrupted);
      expect(row.took, '—');
      expect(row.barStart, 1);
      expect(row.barEnd, 1);
    });

    test('its time scale ends at its last event, and it has no end row: '
        'its journal has not ended', () {
      final session = interrupted();
      final scale = timeScale(session, at(2000));
      expect((scale.start, scale.end), (at(0), at(700)));
      expect(
        logRows(
          session,
          effects: session.state.effects,
          places: places,
          now: now,
        ).last,
        isA<EffectRow>(),
      );
    });

    test('runs as before while its process runs or is not known to', () {
      for (final alive in [true, null]) {
        final session = (mockupJournal()..owned(testOwner, alive: alive)).data;
        final last = effectRows(session).last;
        expect(last.status, StartOutcome.running);
        expect(last.striped, isTrue);
        expect(last.duration, const Duration(seconds: 746 - 612));
        expect(timeScale(session, now).end, now);
      }
    });
  });

  test("a failed effect's row shows its error, took until it failed", () {
    final session = (Journal(
      'a1b2-session',
      workflow: 'inPlace',
    )..effect('plan', 0, end: 6, failed: true, place: copiesAt(4))).data;
    final row = effectRows(session).single;
    expect(row.detail, 'StateError: plan failed');
    expect(row.failure, isTrue);
    expect(row.took, '6s');
  });

  test('an effect not on the graph says so', () {
    final session =
        (Journal('a1b2-session', workflow: 'inPlace')
              ..effect('stray', 0, end: 6, place: 'lib/old.dart:3')
              ..effect('placeless', 6, end: 7))
            .data;
    final rows = effectRows(session);
    expect(rows.map((row) => row.detail), [notOnGraph, notOnGraph]);
    expect(rows.map((row) => row.failure), [false, false]);
  });

  test('an effect in copies names them', () {
    final session = mockup();
    final second = session.state.effects[1].effectId;
    final rows = effectRows(
      session,
      copyOf: (effectId) => effectId == second ? 'pkg 2' : null,
    );
    expect(rows.map((row) => row.copy), [null, 'pkg 2', null, null]);
  });

  test('only the effects given, in their order', () {
    final session = mockup();
    final rows = logRows(
      session,
      effects: session.state.effects.skip(1).take(2),
      places: places,
      now: now,
      end: false,
    );
    expect(rows.length, 2);
  });

  test('an ended session ends with how it ended, unless the end is left '
      'out', () {
    final finished = Journal('a1b2-session', workflow: 'inPlace')
      ..effect('plan', 0, end: 6, place: copiesAt(4))
      ..finish(7);
    final end =
        logRows(
              finished.data,
              effects: finished.data.state.effects,
              places: places,
              now: now,
            ).last
            as EndRow;
    expect(end.text, 'Session finished');
    expect(end.atText, '14:03:18');
    final failed = Journal('a1b2-session', workflow: 'inPlace')
      ..effect('plan', 0, end: 6, place: copiesAt(4))
      ..fail(7, 'StateError: plan failed');
    final failure =
        logRows(
              failed.data,
              effects: failed.data.state.effects,
              places: places,
              now: now,
            ).last
            as EndRow;
    expect(failure.text, 'Session failed: StateError: plan failed');
    expect(failure.status, SessionStatus.failed);
    expect(
      logRows(
        failed.data,
        effects: failed.data.state.effects,
        places: places,
        now: now,
        end: false,
      ).last,
      isA<EffectRow>(),
    );
    expect(
      logRows(
        mockup(),
        effects: mockup().state.effects,
        places: places,
        now: now,
      ).last,
      isA<EffectRow>(),
      reason: 'a running session has not ended',
    );
  });

  test("a row's bar sits on the time scale of the session", () {
    final rows = effectRows(mockup());
    expect(rows.first.barStart, 0);
    expect(rows.first.barEnd, closeTo(149 / 746, 1e-9));
    expect(rows.last.barStart, closeTo(612 / 746, 1e-9));
    expect(rows.last.barEnd, 1);
  });

  test("the time scale runs from the session's start to its end, or to now "
      'while it runs', () {
    final running = timeScale(mockup(), now);
    expect((running.start, running.end), (at(0), now));
    final done = Journal('a1b2-session', workflow: 'inPlace')
      ..effect('plan', 0, end: 184)
      ..finish(184);
    final ended = timeScale(done.data, now);
    expect((ended.start, ended.end), (at(0), at(184)));
    expect(ended.fraction(at(92)), 0.5);
  });

  test("the timeline's axis reads the time from the session's start at its "
      'start, middle and end, rounded down to the largest unit its middle '
      'has a whole one of', () {
    List<String> axis(num seconds) => TimeScale(at(0), at(seconds)).axis;
    expect(axis(746), ['0m', '6m', '12m']);
    expect(axis(2 * 3600 + 54 * 60 + 27), ['0m', '1h', '2h']);
    expect(axis(90 * 60), ['0m', '45m', '90m']);
    expect(axis(80), ['0s', '40s', '80s']);
    expect(axis(31), ['0s', '15s', '31s']);
    expect(axis(0), ['0s', '0s', '0s']);
  });

  group('runs of calls (ui-spec «Logs»)', () {
    List<LogRow> rows({Set<String> open = const {}}) =>
        publishingRows(open: open);

    String describe(LogRow row) => switch (row) {
      RunRow(:final name, :final runText, :final depth) =>
        '$depth $name $runText',
      EffectRow(:final name, :final depth) => '$depth $name',
      EndRow() => 'end',
    };

    test('each run of a call is one row, in place of its first effect, '
        'numbered in the order the runs started', () {
      expect([for (final row in rows()) describe(row)], [
        '0 plan',
        '0 publish() run 1 · 2 effects',
        '0 publish() run 2 · 2 effects',
        '0 publish() run 3 · 2 effects',
        '0 announce',
      ]);
    });

    test("a run's sign weighs its effects: failed, then running, then "
        'finished; its time runs from its first start to its last end', () {
      final runs = rows().whereType<RunRow>().toList();
      expect([for (final run in runs) run.status], [
        StartOutcome.finished,
        StartOutcome.failed,
        StartOutcome.running,
      ]);
      expect(runs.first.started, clockTime(at(10)));
      expect(runs.first.duration, const Duration(seconds: 30));
      expect(runs.last.duration, const Duration(seconds: 100 - 12));
      expect(runs.first.barStart, closeTo(10 / 100, 1e-9));
      expect(runs.first.barEnd, closeTo(40 / 100, 1e-9));
      expect(runs.last.striped, isTrue);
      expect(runs.first.holds(publishingSession().state.effects[1].effectId), isTrue);
      expect(runs.first.holds(publishingSession().state.effects[3].effectId), isFalse);
    });

    test(
      "a run's bar is its effects' bars, each in the color of its state",
      () {
        final runs = rows().whereType<RunRow>().toList();
        String describe(BarPart part) =>
            '${(part.start * 100).round()}-${(part.end * 100).round()} '
            '${part.status.name}';
        expect(
          [for (final part in runs[1].parts) describe(part)],
          ['11-21 finished', '31-41 failed'],
        );
        expect(
          [for (final part in runs[2].parts) describe(part)],
          ['12-22 finished', '32-100 running'],
        );
      },
    );

    test('an open run has its effects under it, a level deeper', () {
      final second = rows().whereType<RunRow>().elementAt(1);
      expect(second.open, isFalse);
      final opened = rows(open: {second.key});
      expect([for (final row in opened) describe(row)], [
        '0 plan',
        '0 publish() run 1 · 2 effects',
        '0 publish() run 2 · 2 effects',
        '1 upload',
        '1 verify',
        '0 publish() run 3 · 2 effects',
        '0 announce',
      ]);
      expect(opened.whereType<RunRow>().elementAt(1).open, isTrue);
    });

    test('the calls are those of the body and of its copies', () {
      final viaCall = file.functions['lib/copies.dart#viaCall']!;
      expect([for (final call in callsIn(viaCall.body)) call.functions], [
        ['lib/copies.dart#publish'],
      ]);
      expect(callsIn(publishingWorkflow.body).single.id, '2');
    });
  });
}
