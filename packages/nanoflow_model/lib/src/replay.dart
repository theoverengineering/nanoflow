import 'events.dart';

/// Where a session is, as its last event tells.
enum SessionStatus {
  /// The last event is neither `session-finished` nor `session-failed`.
  running,

  /// The last event is `session-finished`.
  finished,

  /// The last event is `session-failed`.
  failed,
}

/// Where an effect is, as the events after its last `effect-started` tell.
enum EffectStatus {
  /// No `effect-finished` or `effect-failed` after the last `effect-started`.
  running,

  /// An `effect-finished` after the last `effect-started`.
  finished,

  /// An `effect-failed` after the last `effect-started`.
  failed,
}

/// What replaying a session's journal says about one effect.
final class EffectState {
  const EffectState({
    required this.effectId,
    required this.status,
    required this.starts,
    required this.startedAt,
    required this.finishedAt,
    required this.outputId,
    required this.error,
  });

  final String effectId;

  final EffectStatus status;

  /// How many times the effect ran live: the number of its `effect-started`.
  final int starts;

  /// The time of the first `effect-started`.
  final DateTime startedAt;

  /// The time of the outcome of the last start; `null` while the effect runs.
  final DateTime? finishedAt;

  /// The `outputId` of `effect-finished`; `null` unless the effect finished.
  final String? outputId;

  /// The `error` of `effect-failed`; `null` unless the effect failed.
  final String? error;
}

/// What replaying a session's journal says about the session.
///
/// Never stored: the state is computed again from the events.
final class SessionState {
  const SessionState({
    required this.status,
    required this.effects,
    required this.startedAt,
    required this.finishedAt,
    required this.outputId,
    required this.error,
    required this.codes,
    required this.graphIds,
  });

  final SessionStatus status;

  /// The effects in the order of their first `effect-started`.
  final List<EffectState> effects;

  /// The time of `session-started`; `null` when the journal has none.
  final DateTime? startedAt;

  /// The time of the last event once the session has ended; `null` while it
  /// runs.
  final DateTime? finishedAt;

  /// The `outputId` of `session-finished`; `null` unless the session
  /// finished.
  final String? outputId;

  /// The `error` of `session-failed`; `null` unless the session failed.
  final String? error;

  /// The hashes of the code that ran the session, in order: of
  /// `session-started`, then of each `session-resumed`.
  final List<String?> codes;

  /// The documents with the graph snapshots of the `session-resumed` events
  /// that have one, in order.
  final List<String> graphIds;
}

/// The state of a session after [events], which are in the order of its
/// journal.
///
/// Events this version does not know are skipped. An outcome of an effect with
/// no `effect-started` changes no effect. Replaying never fails.
SessionState replaySession(List<Event> events) {
  // Insertion order is the order of the first `effect-started`.
  final effects = <String, _Effect>{};
  final codes = <String?>[];
  final graphIds = <String>[];
  DateTime? startedAt;
  KnownEvent? last;

  for (final event in events) {
    if (event is! KnownEvent) continue;
    last = event;
    switch (event) {
      case SessionStarted(:final time, :final code):
        startedAt ??= time;
        codes.add(code);
      case SessionResumed(:final code, :final graphId):
        codes.add(code);
        if (graphId != null) graphIds.add(graphId);
      case EffectStarted(:final effectId, :final time):
        (effects[effectId] ??= _Effect(effectId, time)).start();
      case EffectFinished(:final effectId, :final time, :final outputId):
        effects[effectId]?.end(EffectStatus.finished, time, outputId: outputId);
      case EffectFailed(:final effectId, :final time, :final error):
        effects[effectId]?.end(EffectStatus.failed, time, error: error);
      case SessionFinished() || SessionFailed():
        break;
    }
  }

  final (status, finishedAt, outputId, error) = switch (last) {
    SessionFinished(:final time, :final outputId) => (
      SessionStatus.finished,
      time,
      outputId,
      null,
    ),
    SessionFailed(:final time, :final error) => (
      SessionStatus.failed,
      time,
      null,
      error,
    ),
    _ => (SessionStatus.running, null, null, null),
  };
  return SessionState(
    status: status,
    effects: List.unmodifiable([
      for (final effect in effects.values) effect.freeze(),
    ]),
    startedAt: startedAt,
    finishedAt: finishedAt,
    outputId: outputId,
    error: error,
    codes: List.unmodifiable(codes),
    graphIds: List.unmodifiable(graphIds),
  );
}

/// An effect while its events are being replayed.
class _Effect {
  _Effect(this.effectId, this.startedAt);

  final String effectId;
  final DateTime startedAt;
  int starts = 0;
  EffectStatus status = EffectStatus.running;
  DateTime? finishedAt;
  String? outputId;
  String? error;

  /// A new start: the outcome of the start before no longer holds.
  void start() {
    starts++;
    status = EffectStatus.running;
    finishedAt = null;
    outputId = null;
    error = null;
  }

  void end(
    EffectStatus status,
    DateTime time, {
    String? outputId,
    String? error,
  }) {
    this.status = status;
    finishedAt = time;
    this.outputId = outputId;
    this.error = error;
  }

  EffectState freeze() => EffectState(
    effectId: effectId,
    status: status,
    starts: starts,
    startedAt: startedAt,
    finishedAt: finishedAt,
    outputId: outputId,
    error: error,
  );
}
