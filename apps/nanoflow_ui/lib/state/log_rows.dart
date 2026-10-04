/// The `Logs` panel: its title and the rows of the effects list
/// (docs/ui-spec.md «Logs»; spec §9 «Логи»): a session's effects in the order
/// of their first `effect-started`, a selected copy's alone. Pure: the time is
/// passed in.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'effect_places.dart';
import 'session_feed.dart';
import 'texts.dart';
import 'visits.dart' show StartOutcome, outcomeOf;

/// What a row says of an effect that is on no node of the graph.
const notOnGraph = 'not on the graph';

/// The title of the `Logs` panel: `8 effects`, `pkg 2 · 3 effects`.
final class LogsHeader {
  const LogsHeader(this.effects, {this.copy});

  /// How many effects the list shows.
  final int effects;

  /// The copy shown, `pkg 2` or `pkg 2 › target 1`; `null` when the list
  /// shows every copy's effects.
  final String? copy;

  String get effectsText => count(effects, 'effect');

  String get text => copy == null ? effectsText : '$copy · $effectsText';
}

/// A row of the effects list.
sealed class LogRow {}

/// An effect.
final class EffectRow extends LogRow {
  EffectRow._({
    required this.effectId,
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

  final String effectId;

  /// The effect's name.
  final String name;

  /// The icon: finished, running, failed, or interrupted — the effect was
  /// running when the process of its session went.
  final StartOutcome status;

  /// After the name: a failed effect's error; [notOnGraph] for an effect on no
  /// node of the graph.
  final String? detail;

  /// Whether [detail] is an error.
  final bool failure;

  /// The copies the effect is in, but those chosen: `pkg 2`, `pkg 2 ›
  /// target 1`.
  final String? copy;

  /// The time of the first `effect-started`: `14:03:11`.
  final String started;

  /// To the outcome of the last start, or to now while the effect runs;
  /// `null` once it is interrupted: when it would have ended is not known.
  final Duration? duration;

  /// [duration] as shown: `2m 29s`; `—` when it is not known.
  String get took => switch (duration) {
    final d? => formatDuration(d),
    null => '—',
  };

  /// How many times the effect started.
  final int starts;

  /// `2 starts` for an effect started more than once.
  String? get startsText => starts > 1 ? '$starts starts' : null;

  /// Where the effect's bar begins and ends on the session's time scale, from
  /// 0 to 1; an interrupted effect's runs to the end of the scale, the
  /// session's last event.
  final double barStart;
  final double barEnd;

  /// A running effect's bar is striped.
  bool get striped => status == StartOutcome.running;
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

/// The common time scale of a session's effect bars: from its start to its
/// end, or to now while it runs — to its last event once its process is
/// gone.
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
  return TimeScale(
    state.startedAt ?? now,
    state.finishedAt ?? session.timeAt(now),
  );
}

/// The rows of [effects] of [session], in their order; an effect in copies
/// named by [copyOf] (`pkg 2`). An [EndRow] follows once the session has
/// ended, unless [end] is false. [places] tells which effects are not on the
/// graph.
List<LogRow> logRows(
  SessionData session, {
  required Iterable<EffectState> effects,
  required EffectPlaces places,
  required DateTime now,
  String? Function(String effectId)? copyOf,
  bool end = true,
}) {
  final scale = timeScale(session, now);
  final state = session.state;
  final ended = state.finishedAt;
  return [
    for (final effect in effects)
      _effectRow(
        effect,
        session,
        places,
        copyOf?.call(effect.effectId),
        now,
        scale,
      ),
    if (end && ended != null) EndRow._(state.status, state.error, ended),
  ];
}

EffectRow _effectRow(
  EffectState effect,
  SessionData session,
  EffectPlaces places,
  String? copy,
  DateTime now,
  TimeScale scale,
) {
  final record = session.effects[effect.effectId];
  final error = effect.status == EffectStatus.failed ? effect.error : null;
  final status = outcomeOf(session, effect);
  final end = effect.finishedAt ?? session.timeAt(now);
  return EffectRow._(
    effectId: effect.effectId,
    name: record?.name ?? '',
    status: status,
    detail:
        error ?? (record == null || places.onGraph(record) ? null : notOnGraph),
    failure: error != null,
    copy: copy,
    started: clockTime(effect.startedAt),
    duration: status == StartOutcome.interrupted
        ? null
        : end.difference(effect.startedAt),
    starts: effect.starts,
    barStart: scale.fraction(effect.startedAt),
    barEnd: scale.fraction(end),
  );
}
