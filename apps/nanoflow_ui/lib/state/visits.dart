/// The visits to a node in a session, and the starts of an effect
/// (docs/ui-spec.md «Окно деталей эффекта»: `Visit 2 of 2`, `Starts`). A visit
/// is an effect on the node, found by its place (D13). Pure.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'effect_places.dart';
import 'session_feed.dart';

/// A visit to a node: one effect on it.
final class Visit {
  Visit(this.record, this.state);

  final Effect record;

  final EffectState state;

  String get effectId => state.effectId;

  String get name => record.name;
}

/// Those of [effects] of [session] whose records [keep] keeps, as visits in
/// the order of [effects]; an effect whose record is not read yet is left out.
List<Visit> _visits(
  SessionData session,
  Iterable<EffectState> effects,
  bool Function(Effect record) keep,
) => [
  for (final effect in effects)
    if (session.effects[effect.effectId] case final record? when keep(record))
      Visit(record, effect),
];

/// The visits to the effect node [node]: those of [effects] of [session] at its
/// place, as [places] finds them.
List<Visit> visitsTo(
  SessionData session,
  Iterable<EffectState> effects,
  EffectPlaces places,
  EffectNode node,
) => _visits(session, effects, (record) => places.isIn(record, node));

/// The visits like the effect [effectId] of [session]: those of [effects] on
/// the nodes it is on ([places]); for an effect on no node, those at its very
/// place with its name. Just the effect, when it is not among [effects].
List<Visit> visitsLike(
  SessionData session,
  Iterable<EffectState> effects,
  EffectPlaces places,
  String effectId,
) {
  final effect = session.effects[effectId];
  if (effect == null) return const [];
  final at = places.of(effect);
  final visits = _visits(
    session,
    effects,
    (record) => at.isEmpty
        ? record.place == effect.place && record.name == effect.name
        : places.of(record).any(at.contains),
  );
  if (visits.any((visit) => visit.effectId == effectId)) return visits;
  final state = session.state.effects.where((s) => s.effectId == effectId);
  return [for (final s in state) Visit(effect, s)];
}

/// The visit a double click on the effect node [node] opens: the last of
/// [effects] of [session] on it; `null` when none is.
Visit? visitToOpen(
  SessionData session,
  Iterable<EffectState> effects,
  EffectPlaces places,
  EffectNode node,
) => visitsTo(session, effects, places, node).lastOrNull;

/// How a start of an effect ended; how an effect stands is how its last start
/// did ([outcomeOf]).
enum StartOutcome {
  /// It goes on: nothing came after it yet.
  running,

  /// `effect-finished`.
  finished,

  /// `effect-failed`.
  failed,

  /// The process running it stopped: another start of the effect came first,
  /// a resume ran the effect again; or nothing came after it, and the
  /// process of its session is gone (`SessionData.interrupted`).
  interrupted,
}

/// How [effect] of [session] stands: as its journal tells, but interrupted
/// while it runs in a session whose process is gone.
StartOutcome outcomeOf(SessionData session, EffectState effect) =>
    switch (effect.status) {
      EffectStatus.running when session.interrupted => StartOutcome.interrupted,
      EffectStatus.running => StartOutcome.running,
      EffectStatus.finished => StartOutcome.finished,
      EffectStatus.failed => StartOutcome.failed,
    };

/// A start of an effect, and how it ended.
typedef EffectStart = ({DateTime at, StartOutcome outcome});

/// Every start of the effect [effectId] of [session], in the order of its
/// journal; the last one interrupted when it was running and the process
/// of the session is gone.
List<EffectStart> startsOf(SessionData session, String effectId) {
  final starts = <EffectStart>[];
  void end(StartOutcome outcome) {
    final last = starts.lastOrNull;
    if (last != null && last.outcome == StartOutcome.running) {
      starts.last = (at: last.at, outcome: outcome);
    }
  }

  for (final event in session.events) {
    switch (event) {
      case EffectStarted(effectId: final id, :final time) when id == effectId:
        end(StartOutcome.interrupted);
        starts.add((at: time, outcome: StartOutcome.running));
      case EffectFinished(effectId: final id) when id == effectId:
        end(StartOutcome.finished);
      case EffectFailed(effectId: final id) when id == effectId:
        end(StartOutcome.failed);
      default:
        break;
    }
  }
  if (session.interrupted) end(StartOutcome.interrupted);
  return starts;
}
