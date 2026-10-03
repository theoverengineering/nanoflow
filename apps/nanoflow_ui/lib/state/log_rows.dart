/// The `Logs` panel: its title and the rows of the steps list
/// (docs/ui-spec.md «Logs»; spec §9 «Логи»): a session's steps in the order
/// of their first `step-started`, a selected copy's alone. Pure: the time is
/// passed in.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'session_feed.dart';
import 'step_places.dart';
import 'texts.dart';

/// What a row says of a step that is on no node of the graph.
const notOnGraph = 'not on the graph';

/// The title of the `Logs` panel: `8 steps`, `copy 2 · 3 steps`.
final class LogsHeader {
  const LogsHeader(this.steps, {this.copy});

  /// How many steps the list shows.
  final int steps;

  /// The copy shown, `copy 2` or `copy 2 › copy 1`; `null` when the list
  /// shows every copy's steps.
  final String? copy;

  String get stepsText => count(steps, 'step');

  String get text => copy == null ? stepsText : '$copy · $stepsText';
}

/// A row of the steps list.
sealed class LogRow {}

/// A step.
final class StepRow extends LogRow {
  StepRow._({
    required this.stepId,
    required this.name,
    required this.status,
    required this.detail,
    required this.failure,
    required this.copy,
    required this.started,
    required this.duration,
    required this.starts,
    required this.barStart,
    required this.barEnd,
  });

  final String stepId;

  /// The step's name.
  final String name;

  /// The icon: finished, running, failed.
  final StepStatus status;

  /// After the name: a failed step's error; [notOnGraph] for a step on no
  /// node of the graph.
  final String? detail;

  /// Whether [detail] is an error.
  final bool failure;

  /// The copy the step is in, `copy 2`, when the list shows every copy's
  /// steps.
  final String? copy;

  /// The time of the first `step-started`: `14:03:11`.
  final String started;

  /// To the outcome of the last start, or to now while the step runs.
  final Duration duration;

  /// [duration] as shown: `2m 29s`.
  String get took => formatDuration(duration);

  /// How many times the step started.
  final int starts;

  /// `2 starts` for a step started more than once.
  String? get startsText => starts > 1 ? '$starts starts' : null;

  /// Where the step's bar begins and ends on the session's time scale, from
  /// 0 to 1.
  final double barStart;
  final double barEnd;

  /// A running step's bar is striped.
  bool get striped => status == StepStatus.running;
}

/// The last row of a session that has ended.
final class EndRow extends LogRow {
  EndRow._(this.status, this.error, this.at);

  /// [SessionStatus.finished] or [SessionStatus.failed].
  final SessionStatus status;

  /// The error of `session-failed`.
  final String? error;

  /// When the session ended.
  final DateTime at;

  /// [at] as the `Started` column shows times: `14:13:51`.
  String get atText => clockTime(at);

  /// `Session finished`, `Session failed: StateError: plan failed`.
  String get text => status == SessionStatus.failed
      ? 'Session failed: $error'
      : 'Session finished';
}

/// The common time scale of a session's step bars: from its start to its
/// end, or to now while it runs.
final class TimeScale {
  TimeScale(this.start, this.end);

  final DateTime start;
  final DateTime end;

  /// Where [t] is on the scale, from 0 at [start] to 1 at [end].
  double fraction(DateTime t) {
    final span = end.difference(start).inMicroseconds;
    if (span <= 0) return 0;
    return (t.difference(start).inMicroseconds / span).clamp(0.0, 1.0);
  }

  /// The labels under the timeline at its start, middle and end: the time
  /// from [start], rounded down to the largest unit — hour, minute, second —
  /// that the middle has a whole one of. `0m 6m 12m` for 12m 26s, `0m 1h 2h`
  /// for 2h 54m, as the mockups have them; `0s 40s 80s` for 80 s.
  List<String> get axis {
    final span = end.difference(start);
    final half = span ~/ 2;
    final (unit, name) = half >= const Duration(hours: 1)
        ? (const Duration(hours: 1), 'h')
        : half >= const Duration(minutes: 1)
        ? (const Duration(minutes: 1), 'm')
        : (const Duration(seconds: 1), 's');
    String label(Duration d) =>
        '${d.inMicroseconds ~/ unit.inMicroseconds}$name';
    return [name == 's' ? '0s' : '0m', label(half), label(span)];
  }
}

/// The time scale of [session] at [now].
TimeScale timeScale(SessionData session, DateTime now) {
  final state = session.state;
  return TimeScale(state.startedAt ?? now, state.finishedAt ?? now);
}

/// The rows of [steps] of [session], in their order; a step of a copy
/// named by its number in [copies], by step id. An [EndRow] follows once
/// the session has ended, unless [end] is false. [places] tells which
/// steps are not on the graph.
List<LogRow> logRows(
  SessionData session, {
  required Iterable<StepState> steps,
  required StepPlaces places,
  required DateTime now,
  Map<String, int> copies = const {},
  bool end = true,
}) {
  final scale = timeScale(session, now);
  final state = session.state;
  final ended = state.finishedAt;
  return [
    for (final step in steps)
      _stepRow(step, session, places, copies[step.stepId], now, scale),
    if (end && ended != null) EndRow._(state.status, state.error, ended),
  ];
}

StepRow _stepRow(
  StepState step,
  SessionData session,
  StepPlaces places,
  int? copy,
  DateTime now,
  TimeScale scale,
) {
  final record = session.steps[step.stepId];
  final error = step.status == StepStatus.failed ? step.error : null;
  final end = step.finishedAt ?? now;
  return StepRow._(
    stepId: step.stepId,
    name: record?.name ?? '',
    status: step.status,
    detail:
        error ??
        (record == null || places.onGraph(record.place) ? null : notOnGraph),
    failure: error != null,
    copy: copy == null ? null : 'copy $copy',
    started: clockTime(step.startedAt),
    duration: end.difference(step.startedAt),
    starts: step.starts,
    barStart: scale.fraction(step.startedAt),
    barEnd: scale.fraction(end),
  );
}
