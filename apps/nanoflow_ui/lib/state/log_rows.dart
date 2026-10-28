/// The `Logs` panel: its title and the rows of the effects list
/// (docs/ui-spec.md «Logs»; spec §9 «Логи»): a session's effects in the order
/// of their first `effect-started`, a selected copy's alone; each run of a
/// call on one row, opened to show its effects. Pure: the time is passed in.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'copies.dart' show chainsIn;
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

/// A row with a bar on the timeline: an effect, or a run of a call.
sealed class TimedRow extends LogRow {
  TimedRow({
    required this.status,
    required this.copy,
    required this.started,
    required this.duration,
    required this.barStart,
    required this.barEnd,
    required this.depth,
  });

  /// What tells the row's bar apart: an effect's id, a run's key.
  String get barId;

  /// The icon: finished, running, failed, or interrupted — the effect was
  /// running when the process of its session went. A run's is that of the
  /// effect in it that weighs most: failed, running, interrupted, finished.
  final StartOutcome status;

  /// The copies the effect is in, but those chosen: `pkg 2`, `pkg 2 ›
  /// target 1`; a run's, those its first effect is in.
  final String? copy;

  /// The time of the first `effect-started`: `14:03:11`.
  final String started;

  /// To the outcome of the last start, or to now while the effect runs;
  /// `null` once it is interrupted: when it would have ended is not known.
  /// A run's, from its first effect's start to its last effect's end.
  final Duration? duration;

  /// [duration] as shown: `2m 29s`; `—` when it is not known.
  String get took => switch (duration) {
    final d? => formatDuration(d),
    null => '—',
  };

  /// Where the bar begins and ends on the session's time scale, from 0 to 1;
  /// an interrupted effect's runs to the end of the scale, the session's
  /// last event.
  final double barStart;
  final double barEnd;

  /// A running effect's bar is striped.
  bool get striped => status == StartOutcome.running;

  /// How many runs opened the row is in: 0 for one not in a run.
  final int depth;
}

/// An effect.
final class EffectRow extends TimedRow {
  EffectRow._({
    required this.effectId,
    required this.name,
    required super.status,
    required this.detail,
    required this.failure,
    required super.copy,
    required super.started,
    required super.duration,
    required this.starts,
    required super.barStart,
    required super.barEnd,
    required super.depth,
  });

  final String effectId;

  @override
  String get barId => effectId;

  /// The effect's name.
  final String name;

  /// After the name: a failed effect's error; [notOnGraph] for an effect on no
  /// node of the graph.
  final String? detail;

  /// Whether [detail] is an error.
  final bool failure;

  /// How many times the effect started.
  final int starts;

  /// `2 starts` for an effect started more than once.
  String? get startsText => starts > 1 ? '$starts starts' : null;
}

/// A run of a call (docs/ui-spec.md «Logs»): the chain of its effects by
/// `after`, as a call's runs are counted ([chainsIn]), on one row where its
/// first effect would be; opened, its effects are under it, a run of each
/// call in its function on one row again.
final class RunRow extends TimedRow {
  RunRow._({
    required this.key,
    required this.name,
    required this.number,
    required this._effectIds,
    required this.open,
    required super.status,
    required super.copy,
    required super.started,
    required super.duration,
    required super.barStart,
    required super.barEnd,
    required super.depth,
  });

  /// The run's key, the same as long as the session is shown: the keys of the
  /// runs it is in, the call, and its first effect.
  final String key;

  @override
  String get barId => key;

  /// The call: its function with `()`, `compress()`.
  final String name;

  /// From 1, the runs of the call in the order they started.
  final int number;

  final Set<String> _effectIds;

  /// Whether the effect [effectId] is in the run, at any depth.
  bool holds(String? effectId) => _effectIds.contains(effectId);

  /// How many effects are in the run, at any depth.
  int get effects => _effectIds.length;

  /// Whether its effects are shown under it.
  final bool open;

  /// After the name: `run 2 · 27 effects`.
  String get runText => 'run $number · ${count(effects, 'effect')}';
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
/// named by [copyOf] (`pkg 2`). The effects in each of [calls] are its runs,
/// a [RunRow] each in place of its first effect; those whose key is in
/// [open] have their effects under them, a run of each call in its function
/// on one row again. An [EndRow] follows once the session has ended, unless
/// [end] is false. [places] tells which effects are not on the graph.
List<LogRow> logRows(
  SessionData session, {
  required Iterable<EffectState> effects,
  required EffectPlaces places,
  required DateTime now,
  String? Function(String effectId)? copyOf,
  List<CallNode> calls = const [],
  Set<String> open = const {},
  bool end = true,
}) {
  final state = session.state;
  final ended = state.finishedAt;
  final rows = _Rows(session, places, now, copyOf, open)
    ..add([...effects], calls, depth: 0, key: '', path: Set.identity());
  return [
    ...rows.rows,
    if (end && ended != null) EndRow._(state.status, state.error, ended),
  ];
}

/// The calls in [body] and in the bodies of its copies, whose effects the
/// `Logs` put in runs: those of the workflow's body, or of a called graph
/// opened.
List<CallNode> callsIn(GraphBody body) => [
  for (final node in body.nodes)
    ...switch (node) {
      final CallNode call => [call],
      CopiesNode(:final body) => callsIn(body),
      _ => const <CallNode>[],
    },
];

/// A run of [call]: [effects], a chain by `after`, the [number]th of the call.
typedef _Run = ({
  CallNode call,
  String key,
  int number,
  List<EffectState> effects,
});

/// The rows [logRows] builds, row by row.
final class _Rows {
  _Rows(this.session, this.places, this.now, this.copyOf, this.open)
    : scale = timeScale(session, now);

  final SessionData session;
  final EffectPlaces places;
  final DateTime now;
  final String? Function(String effectId)? copyOf;
  final Set<String> open;
  final TimeScale scale;

  final rows = <LogRow>[];

  /// Adds the rows of [effects], [depth] runs deep: the runs of each of
  /// [calls] but those on [path] — a call in its own function —, keyed after
  /// [key], each on one row and its effects under it when open; the other
  /// effects one row each.
  void add(
    List<EffectState> effects,
    List<CallNode> calls, {
    required int depth,
    required String key,
    required Set<CallNode> path,
  }) {
    final runOf = <String, _Run>{};
    for (final call in calls) {
      if (path.contains(call)) continue;
      // An effect in two calls of one function is in the first's runs.
      final chains = chainsIn(
        places.within(call),
        places: places,
        session: session,
        effects: [
          for (final effect in effects)
            if (!runOf.containsKey(effect.effectId)) effect,
        ],
      );
      var number = 0;
      for (final MapEntry(key: first, value: chain) in chains.entries) {
        final run = (
          call: call,
          key: '$key/${call.place}#${call.id}:$first',
          number: ++number,
          effects: chain,
        );
        for (final effect in chain) {
          runOf[effect.effectId] = run;
        }
      }
    }
    final added = <String>{};
    for (final effect in effects) {
      final run = runOf[effect.effectId];
      if (run == null) {
        rows.add(_effectRow(effect, depth));
      } else if (added.add(run.key)) {
        final opened = open.contains(run.key);
        rows.add(_runRow(run, depth, opened));
        if (opened) {
          add(
            run.effects,
            [
              for (final function in places.calledBy(run.call))
                ...callsIn(function.body),
            ],
            depth: depth + 1,
            key: run.key,
            path: Set.identity()
              ..addAll(path)
              ..add(run.call),
          );
        }
      }
    }
  }

  EffectRow _effectRow(EffectState effect, int depth) {
    final record = session.effects[effect.effectId];
    final error = effect.status == EffectStatus.failed ? effect.error : null;
    final status = outcomeOf(session, effect);
    final end = effect.finishedAt ?? session.timeAt(now);
    return EffectRow._(
      effectId: effect.effectId,
      name: record?.name ?? '',
      status: status,
      detail:
          error ??
          (record == null || places.onGraph(record) ? null : notOnGraph),
      failure: error != null,
      copy: copyOf?.call(effect.effectId),
      started: clockTime(effect.startedAt),
      duration: status == StartOutcome.interrupted
          ? null
          : end.difference(effect.startedAt),
      starts: effect.starts,
      barStart: scale.fraction(effect.startedAt),
      barEnd: scale.fraction(end),
      depth: depth,
    );
  }

  RunRow _runRow(_Run run, int depth, bool open) {
    final effects = run.effects;
    final outcomes = {for (final e in effects) outcomeOf(session, e)};
    final status = [
      StartOutcome.failed,
      StartOutcome.running,
      StartOutcome.interrupted,
    ].firstWhere(outcomes.contains, orElse: () => StartOutcome.finished);
    final start = effects
        .map((effect) => effect.startedAt)
        .reduce((a, b) => b.isBefore(a) ? b : a);
    final end = effects
        .map((effect) => effect.finishedAt ?? session.timeAt(now))
        .reduce((a, b) => b.isAfter(a) ? b : a);
    final functions = places.calledBy(run.call);
    final name = functions.isEmpty
        ? run.call.functions.firstOrNull?.split('#').last ?? ''
        : functions.first.name;
    return RunRow._(
      key: run.key,
      name: '$name()',
      number: run.number,
      effectIds: {for (final effect in effects) effect.effectId},
      open: open,
      status: status,
      copy: copyOf?.call(effects.first.effectId),
      started: clockTime(start),
      duration: status == StartOutcome.interrupted
          ? null
          : end.difference(start),
      barStart: scale.fraction(start),
      barEnd: scale.fraction(end),
      depth: depth,
    );
  }
}
