import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/log_rows.dart';
import 'package:nanoflow_ui/state/session_feed.dart';
import 'package:nanoflow_ui/state/step_places.dart';

import 'support.dart';

void main() {
  final file = copiesGraphFile();
  final places = StepPlaces.of(
    file.functions['lib/copies.dart#inPlace'],
    file.functions,
  );
  final now = at(746);

  /// review's steps as docs/design/graph.png has them, at [places] of
  /// inPlace: collect and inspect done, inspect again, then notify running.
  SessionData mockup() =>
      (Journal('a1b2-session', workflow: 'inPlace')
            ..step('collect', 0, end: 149, place: copiesAt(4))
            ..step('inspect', 149, end: 341, place: copiesAt(7))
            ..step(
              'inspect',
              341,
              end: 612,
              place: copiesAt(7),
              restarts: [400],
            )
            ..step('notify', 612, place: copiesAt(8)))
          .data;

  List<StepRow> stepRows(SessionData session, {Map<String, int>? copies}) => [
    for (final row in logRows(
      session,
      steps: session.state.steps,
      places: places,
      copies: copies ?? const {},
      now: now,
    ))
      if (row is StepRow) row,
  ];

  group('the header (ui-spec «Logs»)', () {
    test('counts the steps shown', () {
      expect(const LogsHeader(8).text, '8 steps');
      expect(const LogsHeader(1).text, '1 step');
    });

    test('names the copy shown', () {
      expect(const LogsHeader(3, copy: 'copy 2').text, 'copy 2 · 3 steps');
    });
  });

  test('a row is the step, its first start, and how long it took, in the '
      'order of first step-started', () {
    final rows = stepRows(mockup());
    expect(
      [for (final row in rows) row.name],
      ['collect', 'inspect', 'inspect', 'notify'],
    );
    final first = rows.first;
    expect(first.started, '14:03:11');
    expect(first.took, '2m 29s');
    expect(first.status, StepStatus.finished);
    expect(first.detail, isNull);
    expect(first.startsText, isNull);
  });

  test('a restarted step is marked 2 starts', () {
    expect(stepRows(mockup())[2].startsText, '2 starts');
  });

  test('a running step ticks until now and is striped', () {
    final last = stepRows(mockup()).last;
    expect(last.duration, const Duration(seconds: 746 - 612));
    expect(last.striped, isTrue);
  });

  test("a failed step's row shows its error, took until it failed", () {
    final session = (Journal(
      'a1b2-session',
      workflow: 'inPlace',
    )..step('plan', 0, end: 6, failed: true, place: copiesAt(4))).data;
    final row = stepRows(session).single;
    expect(row.detail, 'StateError: plan failed');
    expect(row.failure, isTrue);
    expect(row.took, '6s');
  });

  test('a step not on the graph says so', () {
    final session =
        (Journal('a1b2-session', workflow: 'inPlace')
              ..step('stray', 0, end: 6, place: 'lib/old.dart:3')
              ..step('placeless', 6, end: 7))
            .data;
    final rows = stepRows(session);
    expect(rows.map((row) => row.detail), [notOnGraph, notOnGraph]);
    expect(rows.map((row) => row.failure), [false, false]);
  });

  test('a step of a copy names it', () {
    final session = mockup();
    final rows = stepRows(session, copies: {session.state.steps[1].stepId: 2});
    expect(rows.map((row) => row.copy), [null, 'copy 2', null, null]);
  });

  test('only the steps given, in their order', () {
    final session = mockup();
    final rows = logRows(
      session,
      steps: session.state.steps.skip(1).take(2),
      places: places,
      now: now,
      end: false,
    );
    expect(rows.length, 2);
  });

  test('an ended session ends with how it ended, unless the end is left '
      'out', () {
    final finished = Journal('a1b2-session', workflow: 'inPlace')
      ..step('plan', 0, end: 6, place: copiesAt(4))
      ..finish(7);
    final end =
        logRows(
              finished.data,
              steps: finished.data.state.steps,
              places: places,
              now: now,
            ).last
            as EndRow;
    expect(end.text, 'Session finished');
    expect(end.atText, '14:03:18');
    final failed = Journal('a1b2-session', workflow: 'inPlace')
      ..step('plan', 0, end: 6, place: copiesAt(4))
      ..fail(7, 'StateError: plan failed');
    final failure =
        logRows(
              failed.data,
              steps: failed.data.state.steps,
              places: places,
              now: now,
            ).last
            as EndRow;
    expect(failure.text, 'Session failed: StateError: plan failed');
    expect(failure.status, SessionStatus.failed);
    expect(
      logRows(
        failed.data,
        steps: failed.data.state.steps,
        places: places,
        now: now,
        end: false,
      ).last,
      isA<StepRow>(),
    );
    expect(
      logRows(
        mockup(),
        steps: mockup().state.steps,
        places: places,
        now: now,
      ).last,
      isA<StepRow>(),
      reason: 'a running session has not ended',
    );
  });

  test("a row's bar sits on the time scale of the session", () {
    final rows = stepRows(mockup());
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
      ..step('plan', 0, end: 184)
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
}
