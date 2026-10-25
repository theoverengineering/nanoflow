/// Which nodes of the graph a session's effects are on (spec §9 «Эффекты на
/// графе», D13): an effect is on the effect nodes whose place is the effect's —
/// the path compared by its end, since an effect records where `f.effect` was
/// called as the stack printed it — and, of those, on the ones of its name.
/// Two effects called on one line share a place, and their names tell them
/// apart; an effect whose name no node there has is on all of them, since a
/// node of a name given by an expression is named by its source. Several
/// nodes share a place and a name when a `finally` is drawn once for each
/// way out of its `try`; the effect is on them all. An effect without a place,
/// or at no node, is not on the graph. Pure.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

/// Whether an effect that ran at [effectPlace] is at the effect node at
/// [nodePlace]: the same place, or one that ends with it after a `/` (a
/// path the effect recorded from outside the project directory).
bool isPlaceOf(String effectPlace, String nodePlace) =>
    effectPlace == nodePlace || effectPlace.endsWith('/$nodePlace');

/// The effect nodes of a workflow's graph, and which of them an effect is on.
final class EffectPlaces {
  EffectPlaces._(this._workflow, this._functions, this.nodes);

  /// The effect nodes of [workflow] and of all it reaches in [functions]: the
  /// bodies of its copies, the functions it calls, and so on; none without
  /// a [workflow].
  factory EffectPlaces.of(
    GraphFunction? workflow,
    Map<String, GraphFunction> functions,
  ) {
    final places = EffectPlaces._(workflow?.id, functions, const {});
    return EffectPlaces._(workflow?.id, functions, {
      if (workflow != null) ...places._inBody(workflow.body, {workflow.id}),
    });
  }

  /// The id of the workflow; `null` without one.
  final String? _workflow;

  final Map<String, GraphFunction> _functions;

  /// Every effect node the workflow reaches.
  final Set<EffectNode> nodes;

  final Map<(String, String), Set<EffectNode>> _of = {};
  final Map<GraphNode, Set<EffectNode>> _within = Map.identity();
  final Map<String, Set<EffectNode>> _withinFunction = {};

  /// The effect nodes [effect] is on: of those at its place, the ones of its
  /// name, or all of them when none is; none for no effect, an effect without a
  /// place, or one at no node.
  Set<EffectNode> of(Effect? effect) {
    final place = effect?.place;
    if (effect == null || place == null) return const {};
    return _of[(place, effect.name)] ??= () {
      final at = {
        for (final node in nodes)
          if (node.place case final nodePlace? when isPlaceOf(place, nodePlace))
            node,
      };
      final named = {
        for (final node in at)
          if (node.name == effect.name) node,
      };
      return named.isEmpty ? at : named;
    }();
  }

  /// Whether [effect] is on an effect node of the graph.
  bool onGraph(Effect? effect) => of(effect).isNotEmpty;

  /// The effect nodes [node] holds: an effect node itself; for copies, those of
  /// their body and of all it reaches; for a call, those of the bodies of
  /// its functions and of all they reach; none for a condition.
  Set<EffectNode> within(GraphNode node) => _within[node] ??= switch (node) {
    final EffectNode effect => {effect},
    ConditionNode() => const {},
    CopiesNode(:final body) => _inBody(body, const {}),
    CallNode() => _inNode(node, const {}),
  };

  /// The id of the function whose body [body] is, or holds as the body of
  /// copies; `null` for a body of no function of the graph.
  String? ownerOf(GraphBody body) => _owners[body];

  /// Whether [body] is that of a function the workflow calls: the code comes
  /// into it at each call, and may leave it and come into it again with no
  /// effect between. Not the workflow's own — drawn once whether it runs or
  /// calls itself —, nor that of copies, which run once.
  bool isCalled(GraphBody body) => switch (ownerOf(body)) {
    final owner? =>
      owner != _workflow && identical(_functions[owner]?.body, body),
    null => false,
  };

  /// Whether [body] is the workflow's own: the code comes into it once.
  bool isWorkflow(GraphBody body) =>
      _workflow != null && identical(_functions[_workflow]?.body, body);

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

  /// Whether [effect] is on [node] or inside it.
  bool isIn(Effect? effect, GraphNode node) {
    final at = of(effect);
    return at.isNotEmpty && within(node).any(at.contains);
  }

  /// The effect nodes of the body of the function [id] and of all it
  /// reaches: what a call of it alone holds, where [within] a call holds
  /// every function it may go to; none for a function the graph does not
  /// have.
  Set<EffectNode> withinFunction(String id) =>
      _withinFunction[id] ??= switch (_functions[id]) {
        final function? => _inBody(function.body, {id}),
        null => const {},
      };

  /// Whether [effect] is in the body of the function [id] or in what it
  /// calls: on a node [withinFunction] holds. The effects are found among
  /// those of the workflow, so a function it does not reach holds none.
  bool isInFunction(Effect? effect, String id) {
    final at = of(effect);
    return at.isNotEmpty && withinFunction(id).any(at.contains);
  }

  /// The effect nodes in [body] and all it reaches; a function in [entered]
  /// is not entered again: a recursive call holds nothing new.
  Set<EffectNode> _inBody(GraphBody body, Set<String> entered) => {
    for (final node in body.nodes) ..._inNode(node, entered),
  };

  Set<EffectNode> _inNode(GraphNode node, Set<String> entered) =>
      switch (node) {
        final EffectNode effect => {effect},
        ConditionNode() => const {},
        CopiesNode(:final body) => _inBody(body, entered),
        CallNode(:final functions) => {
          for (final id in functions)
            if (_functions[id] case final function? when !entered.contains(id))
              ..._inBody(function.body, {...entered, id}),
        },
      };
}

/// Those of [effects] that are not on the graph of [places]: without a place,
/// or at no effect node; in their order.
List<Effect> effectsNotOnGraph(Iterable<Effect> effects, EffectPlaces places) =>
    [
      for (final effect in effects)
        if (!places.onGraph(effect)) effect,
    ];
