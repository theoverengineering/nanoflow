/// Which nodes of the graph a session's steps are on (spec §9 «Шаги на
/// графе», D13): a step is on every step node whose place is the step's —
/// the path compared by its end, since a step records where `f.step` was
/// called as the stack printed it. Several nodes share a place when a
/// `finally` is drawn once for each way out of its `try`; the step is on
/// them all. A step without a place, or at no node, is not on the graph.
/// Pure.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

/// Whether a step that ran at [stepPlace] is at the step node at
/// [nodePlace]: the same place, or one that ends with it after a `/` (a
/// path the step recorded from outside the project directory).
bool isPlaceOf(String stepPlace, String nodePlace) =>
    stepPlace == nodePlace || stepPlace.endsWith('/$nodePlace');

/// The places of the step nodes of a workflow's graph, and which of them the
/// place of a step is.
final class StepPlaces {
  StepPlaces._(this._functions, this.nodePlaces);

  /// The step nodes of [workflow] and of all it reaches in [functions]: the
  /// bodies of its copies, the functions it calls, and so on; none without
  /// a [workflow].
  factory StepPlaces.of(
    GraphFunction? workflow,
    Map<String, GraphFunction> functions,
  ) {
    final places = StepPlaces._(functions, const {});
    return StepPlaces._(functions, {
      if (workflow != null) ...places._inBody(workflow.body, {workflow.id}),
    });
  }

  final Map<String, GraphFunction> _functions;

  /// The place of every step node the workflow reaches.
  final Set<String> nodePlaces;

  final Map<String, Set<String>> _of = {};
  final Map<GraphNode, Set<String>> _within = Map.identity();

  /// The places of step nodes a step at [place] is at; none for a step
  /// without a place, or at no node.
  Set<String> of(String? place) {
    if (place == null) return const {};
    return _of[place] ??= {
      for (final node in nodePlaces)
        if (isPlaceOf(place, node)) node,
    };
  }

  /// Whether a step at [place] is on a step node of the graph.
  bool onGraph(String? place) => of(place).isNotEmpty;

  /// The places of the step nodes [node] holds: a step's own; for copies,
  /// those of their body and of all it reaches; for a call, those of the
  /// bodies of its functions and of all they reach; none for a condition.
  Set<String> within(GraphNode node) => _within[node] ??= switch (node) {
    StepNode(:final place) => {?place},
    ConditionNode() => const {},
    CopiesNode(:final body) => _inBody(body, const {}),
    CallNode() => _inNode(node, const {}),
  };

  /// Whether a step at [place] is on [node] or inside it.
  bool isIn(String? place, GraphNode node) {
    final at = of(place);
    return at.isNotEmpty && within(node).any(at.contains);
  }

  /// The places of the step nodes in [body] and all it reaches; a function
  /// in [entered] is not entered again: a recursive call holds nothing new.
  Set<String> _inBody(GraphBody body, Set<String> entered) => {
    for (final node in body.nodes) ..._inNode(node, entered),
  };

  Set<String> _inNode(GraphNode node, Set<String> entered) => switch (node) {
    StepNode(:final place) => {?place},
    ConditionNode() => const {},
    CopiesNode(:final body) => _inBody(body, entered),
    CallNode(:final functions) => {
      for (final id in functions)
        if (_functions[id] case final function? when !entered.contains(id))
          ..._inBody(function.body, {...entered, id}),
    },
  };
}

/// Those of [steps] that are not on the graph of [places]: without a place,
/// or at no step node; in their order.
List<Step> stepsNotOnGraph(Iterable<Step> steps, StepPlaces places) => [
  for (final step in steps)
    if (!places.onGraph(step.place)) step,
];
