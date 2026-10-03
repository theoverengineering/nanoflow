/// Which nodes of the graph a session's steps are on (spec §9 «Шаги на
/// графе», D13): a step is on the step nodes whose place is the step's —
/// the path compared by its end, since a step records where `f.step` was
/// called as the stack printed it — and, of those, on the ones of its name.
/// Two steps called on one line share a place, and their names tell them
/// apart; a step whose name no node there has is on all of them, since a
/// node of a name given by an expression is named by its source. Several
/// nodes share a place and a name when a `finally` is drawn once for each
/// way out of its `try`; the step is on them all. A step without a place,
/// or at no node, is not on the graph. Pure.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

/// Whether a step that ran at [stepPlace] is at the step node at
/// [nodePlace]: the same place, or one that ends with it after a `/` (a
/// path the step recorded from outside the project directory).
bool isPlaceOf(String stepPlace, String nodePlace) =>
    stepPlace == nodePlace || stepPlace.endsWith('/$nodePlace');

/// The step nodes of a workflow's graph, and which of them a step is on.
final class StepPlaces {
  StepPlaces._(this._functions, this.nodes);

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

  /// Every step node the workflow reaches.
  final Set<StepNode> nodes;

  final Map<(String, String), Set<StepNode>> _of = {};
  final Map<GraphNode, Set<StepNode>> _within = Map.identity();

  /// The step nodes [step] is on: of those at its place, the ones of its
  /// name, or all of them when none is; none for no step, a step without a
  /// place, or one at no node.
  Set<StepNode> of(Step? step) {
    final place = step?.place;
    if (step == null || place == null) return const {};
    return _of[(place, step.name)] ??= () {
      final at = {
        for (final node in nodes)
          if (node.place case final nodePlace? when isPlaceOf(place, nodePlace))
            node,
      };
      final named = {
        for (final node in at)
          if (node.name == step.name) node,
      };
      return named.isEmpty ? at : named;
    }();
  }

  /// Whether [step] is on a step node of the graph.
  bool onGraph(Step? step) => of(step).isNotEmpty;

  /// The step nodes [node] holds: a step node itself; for copies, those of
  /// their body and of all it reaches; for a call, those of the bodies of
  /// its functions and of all they reach; none for a condition.
  Set<StepNode> within(GraphNode node) => _within[node] ??= switch (node) {
    final StepNode step => {step},
    ConditionNode() => const {},
    CopiesNode(:final body) => _inBody(body, const {}),
    CallNode() => _inNode(node, const {}),
  };

  /// The id of the function whose body [body] is, or holds as the body of
  /// copies; `null` for a body of no function of the graph.
  String? ownerOf(GraphBody body) => _owners[body];

  /// The function of each body of the graph, by the body.
  late final Map<GraphBody, String> _owners = () {
    final owners = Map<GraphBody, String>.identity();
    void own(GraphBody body, String id) {
      owners[body] = id;
      for (final copies in body.nodes.whereType<CopiesNode>()) {
        own(copies.body, id);
      }
    }

    for (final function in _functions.values) {
      own(function.body, function.id);
    }
    return owners;
  }();

  /// The functions [call] calls that the graph has.
  List<GraphFunction> calledBy(CallNode call) => [
    for (final id in call.functions) ?_functions[id],
  ];

  /// Whether [step] is on [node] or inside it.
  bool isIn(Step? step, GraphNode node) {
    final at = of(step);
    return at.isNotEmpty && within(node).any(at.contains);
  }

  /// The step nodes in [body] and all it reaches; a function in [entered]
  /// is not entered again: a recursive call holds nothing new.
  Set<StepNode> _inBody(GraphBody body, Set<String> entered) => {
    for (final node in body.nodes) ..._inNode(node, entered),
  };

  Set<StepNode> _inNode(GraphNode node, Set<String> entered) => switch (node) {
    final StepNode step => {step},
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
    if (!places.onGraph(step)) step,
];
