/// The runs of a call in a session (docs/ui-spec.md «Граф», «Logs»): the
/// chains of the effects in it by `after`. A run's first effect is one whose
/// predecessor — the effect whose key its record's `after` is — lies outside
/// the call (an effect at no place the call holds, or none at all); every
/// other effect of the call belongs to the run of its predecessor. A rerun
/// rewrites a record's `after`: the chain follows the record as it is now.
/// Pure.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'effect_places.dart';
import 'session_feed.dart';

/// [effects] of [session] (by default, all of its effects) on the effect
/// nodes [held], in chains by `after`, by the id of the first effect of each:
/// one whose predecessor is on none of [held], or that has none; every other
/// effect is in the chain of its predecessor. The runs of a call are its
/// chains. An effect whose record has not been given is in none.
Map<String, List<EffectState>> chainsIn(
  Set<EffectNode> held, {
  required EffectPlaces places,
  required SessionData session,
  Iterable<EffectState>? effects,
}) {
  bool inside(Effect? record) => places.of(record).any(held.contains);

  // The first effect of the chain of each effect, by id: every effect walked
  // gets it, so that each chain is walked once.
  final firsts = <String, String>{};
  String firstOf(Effect record) {
    final walked = <String>{};
    var effect = record;
    String first;
    while (true) {
      final known = firsts[effect.id];
      if (known != null) {
        first = known;
        break;
      }
      walked.add(effect.id);
      final after = effect.after;
      final before = after == null ? null : session.effectWithKey(after);
      if (before == null || !inside(before) || walked.contains(before.id)) {
        first = effect.id;
        break;
      }
      effect = before;
    }
    for (final id in walked) {
      firsts[id] = first;
    }
    return first;
  }

  final chains = <String, List<EffectState>>{};
  for (final effect in effects ?? session.state.effects) {
    final record = session.effects[effect.effectId];
    if (!inside(record)) continue;
    (chains[firstOf(record!)] ??= []).add(effect);
  }
  return chains;
}
