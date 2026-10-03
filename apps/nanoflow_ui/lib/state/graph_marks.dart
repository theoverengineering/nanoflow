/// What a session's steps put on the level of the graph the canvas draws
/// (docs/ui-spec.md «Граф»; spec §9 «Шаги на графе», «Копии»): the state of
/// each node, how many steps were on it and how many run there now, how
/// many copies a `copies` node ran, and the nodes of the selected step.
/// Pure.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'copies.dart';
import 'session_feed.dart';
import 'step_places.dart';
import 'texts.dart' show timesText;
import 'visits.dart' show StartOutcome, outcomeOf;

/// A node's state over the steps on it; a later value wins over an earlier
/// one (ui-spec «Граф»).
enum NodeState {
  /// No steps.
  notVisited,

  /// Finished steps.
  visited,

  /// A step was running when the process of its session went: it does not
  /// run, and a resume would run it again.
  interrupted,

  /// A step runs: no `step-finished` or `step-failed` after its last
  /// `step-started`.
  running,

  /// A step failed: it threw the last time it ran.
  failed,
}

/// What the steps put on one node: on a step node those at its place; on a
/// call those in its functions; on copies those in their body.
final class NodeMarks {
  const NodeMarks({
    required this.state,
    required this.steps,
    required this.running,
    this.copies,
  });

  final NodeState state;

  /// How many steps were on the node, or in it.
  final int steps;

  /// How many of them run now: on a step node in copies, how many copies
  /// are on the step. None of an interrupted session's do.
  final int running;

  /// How many copies a `copies` node ran; `null` for any other node.
  final int? copies;

  /// `2×` over a node entered more than once; `null` otherwise.
  String? get visitsText => steps > 1 ? timesText(steps) : null;
}

/// What steps of a session put on the nodes of one body.
final class GraphMarks {
  GraphMarks._(this._marks, this._nodesOf, this.selected);

  /// The marks [steps] of [session] (by default, all of them) put on the
  /// nodes of [body], found by their places with [places]; with the nodes
  /// of the step [selectedStepId] selected. Conditions run no steps: they
  /// have no marks.
  factory GraphMarks.of(
    GraphBody body, {
    required StepPlaces places,
    required SessionData session,
    Iterable<StepState>? steps,
    String? selectedStepId,
  }) {
    final scope = [...(steps ?? session.state.steps)];
    final nodes = [
      for (final node in body.nodes)
        if (node is! ConditionNode) node,
    ];
    List<String> nodesOf(String stepId) {
      final record = session.steps[stepId];
      return [
        for (final node in nodes)
          if (places.isIn(record, node)) node.id,
      ];
    }

    final on = <String, List<StepState>>{for (final node in nodes) node.id: []};
    for (final step in scope) {
      for (final id in nodesOf(step.stepId)) {
        on[id]!.add(step);
      }
    }
    return GraphMarks._(
      {
        for (final node in nodes)
          node.id: _marksOf(
            session,
            on[node.id]!,
            copies: node is CopiesNode
                ? copiesOf(
                    node,
                    places: places,
                    session: session,
                    steps: on[node.id],
                  ).length
                : null,
          ),
      },
      nodesOf,
      selectedStepId == null ? const {} : {...nodesOf(selectedStepId)},
    );
  }

  final Map<String, NodeMarks> _marks;
  final List<String> Function(String stepId) _nodesOf;

  /// The nodes the selected step is on or in: ringed.
  final Set<String> selected;

  /// The marks of the node [id]; `null` for a condition, a marker, or a
  /// node the body does not have.
  NodeMarks? of(String id) => _marks[id];

  /// The nodes of the body the step [stepId] is on or in, in the body's
  /// order; none for a step at no node of it.
  List<String> nodesOf(String stepId) => _nodesOf(stepId);
}

NodeMarks _marksOf(SessionData session, List<StepState> steps, {int? copies}) {
  var state = NodeState.notVisited;
  var running = 0;
  for (final step in steps) {
    final NodeState of;
    switch (outcomeOf(session, step)) {
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
    steps: steps.length,
    running: running,
    copies: copies,
  );
}
