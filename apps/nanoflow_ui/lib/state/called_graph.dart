/// A function the workflows call opened as the main graph of the graph
/// screen (docs/superpowers/specs/2026-10-25-open-as-graph-design.md): the
/// sessions it ran in — its own, run as a workflow, and its parents', the
/// sessions of the workflows that call it — and the effects of a parent's
/// session that ran in it. Pure.
///
/// A parent's session is told by its own places: those of its workflow on
/// the graph it is shown on. An effect ran in the function when it is on a
/// node of the function's body or of what it calls; however many times the
/// session called it, its effects there are on the same nodes.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'effect_places.dart';
import 'session_feed.dart';
import 'sessions.dart' show workflowIdOf;

/// Whether [session] ran [function] of [graph] as its workflow: whose name
/// the graph file lists it under, as it lists the sessions of a workflow
/// (`workflowIdOf`) — the function's id for a workflow of the file, its name
/// for a function the file has as no workflow.
bool ranAsWorkflow(
  SessionData session,
  GraphFile graph,
  GraphFunction function,
) {
  final id = workflowIdOf(graph, session.session.workflow);
  return id == function.id || id == function.name;
}

/// Where the effects of [session] are on [graph], the graph it is shown on:
/// the places of the effect nodes of its workflow (`EffectPlaces.of`);
/// none without [graph], or when it has no such workflow.
EffectPlaces placesOfSession(SessionData session, GraphFile? graph) =>
    EffectPlaces.of(
      graph?.workflowNamed(session.session.workflow),
      graph?.functions ?? const {},
    );

/// Whether the function [functionId] ran in [session]: an effect of it is in
/// the function's body or in what it calls, found by [places], those of the
/// session's workflow (`EffectPlaces.isInFunction`).
bool ranIn(SessionData session, EffectPlaces places, String functionId) =>
    session.effects.values.any(
      (effect) => places.isInFunction(effect, functionId),
    );

/// Those of [effects] of [session] in the body of the function
/// [functionId] or in what it calls, found by [places], in their order:
/// what of a parent's session `Logs` list.
List<EffectState> effectsIn(
  SessionData session,
  Iterable<EffectState> effects,
  EffectPlaces places,
  String functionId,
) => [
  for (final effect in effects)
    if (places.isInFunction(session.effects[effect.effectId], functionId))
      effect,
];
