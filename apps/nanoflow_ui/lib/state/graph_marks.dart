/// What a session's effects put on the level of the graph the canvas draws
/// (docs/ui-spec.md «Граф»; spec §9 «Эффекты на графе», «Развилки», «Копии»):
/// the state of each node, how many effects were on it and how many run there
/// now, the forks their code went through and how many times, how many
/// copies a `copies` node ran, and the nodes of the selected effect. Pure.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'copies.dart';
import 'effect_places.dart';
import 'passes.dart';
import 'session_feed.dart';
import 'texts.dart' show timesText;
import 'visits.dart' show StartOutcome, outcomeOf;

/// A node's state over the effects on it; a later value wins over an earlier
/// one (ui-spec «Граф»).
enum NodeState {
  /// No effects.
  notVisited,

  /// Finished effects.
  visited,

  /// An effect was running when the process of its session went: it does not
  /// run, and a resume would run it again.
  interrupted,

  /// An effect runs: no `effect-finished` or `effect-failed` after its last
  /// `effect-started`.
  running,

  /// An effect failed: it threw the last time it ran.
  failed,
}

/// What the effects put on one node: on an effect node those at its place; on a
/// call those in its functions; on copies those in their body; on a fork the
/// runs of their code that went through it.
final class NodeMarks {
  const NodeMarks({
    required this.state,
    required this.effects,
    required this.running,
    this.copies,
  });

  final NodeState state;

  /// How many effects were on the node, or in it; on a fork, how many runs
  /// of the code went through it.
  final int effects;

  /// How many of them run now: on an effect node in copies, how many copies
  /// are on the effect. None of an interrupted session's do.
  final int running;

  /// How many copies a `copies` node ran; `null` for any other node.
  final int? copies;

  /// `2×` over a node entered more than once; `null` otherwise.
  String? get visitsText => effects > 1 ? timesText(effects) : null;
}

/// What effects of a session put on the nodes of one body.
final class GraphMarks {
  GraphMarks._(this._marks, this._nodesOf, this.selected, this.passes);

  /// The marks [effects] of [session] (by default, all of them) put on the
  /// nodes of [body], found by their places with [places]; with the nodes
  /// of the effect [selectedEffectId] selected.
  ///
  /// A fork runs no effects: it is visited when the code of those effects
  /// went through it ([passes]), as many times as runs did, and has no
  /// marks otherwise — drawn plain, as with no session: that no way is
  /// found through it does not tell the code did not go there.
  factory GraphMarks.of(
    GraphBody body, {
    required EffectPlaces places,
    required SessionData session,
    Iterable<EffectState>? effects,
    String? selectedEffectId,
  }) {
    final scope = [...(effects ?? session.state.effects)];
    final nodes = [
      for (final node in body.nodes)
        if (node is! ConditionNode) node,
    ];
    List<String> nodesOf(String effectId) {
      final record = session.effects[effectId];
      return [
        for (final node in nodes)
          if (places.isIn(record, node)) node.id,
      ];
    }

    final on = <String, List<EffectState>>{
      for (final node in nodes) node.id: [],
    };
    for (final effect in scope) {
      for (final id in nodesOf(effect.effectId)) {
        on[id]!.add(effect);
      }
    }
    final passes = Passes.of(
      body,
      places: places,
      session: session,
      effects: scope,
    );
    return GraphMarks._(
      {
        for (final node in body.nodes)
          if (node is ConditionNode && passes.of(node.id) > 0)
            node.id: NodeMarks(
              state: NodeState.visited,
              effects: passes.of(node.id),
              running: 0,
            ),
        for (final node in nodes)
          node.id: _marksOf(
            session,
            on[node.id]!,
            copies: node is CopiesNode
                ? copiesOf(
                    node,
                    places: places,
                    session: session,
                    effects: on[node.id],
                  ).length
                : null,
          ),
      },
      nodesOf,
      selectedEffectId == null ? const {} : {...nodesOf(selectedEffectId)},
      passes,
    );
  }

  final Map<String, NodeMarks> _marks;
  final List<String> Function(String effectId) _nodesOf;

  /// The nodes the selected effect is on or in: ringed.
  final Set<String> selected;

  /// The forks the effects went through on the body, and the edges they
  /// took or could not have taken.
  final Passes passes;

  /// The marks of the node [id]; `null` for a fork the code did not go
  /// through, a marker, or a node the body does not have.
  NodeMarks? of(String id) => _marks[id];

  /// The nodes of the body the effect [effectId] is on or in, in the body's
  /// order; none for an effect at no node of it.
  List<String> nodesOf(String effectId) => _nodesOf(effectId);
}

NodeMarks _marksOf(
  SessionData session,
  List<EffectState> effects, {
  int? copies,
}) {
  var state = NodeState.notVisited;
  var running = 0;
  for (final effect in effects) {
    final NodeState of;
    switch (outcomeOf(session, effect)) {
      case StartOutcome.running:
        running++;
        of = NodeState.running;
      case StartOutcome.interrupted:
        of = NodeState.interrupted;
      case StartOutcome.failed:
        of = NodeState.failed;
      case StartOutcome.finished:
        of = NodeState.visited;
    }
    if (of.index > state.index) state = of;
  }
  return NodeMarks(
    state: state,
    effects: effects.length,
    running: running,
    copies: copies,
  );
}
