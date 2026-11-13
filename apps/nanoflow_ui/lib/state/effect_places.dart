/// Which nodes of the graph a session's effects are on (spec §9 «Эффекты на
/// графе», D13): an effect is on the effect nodes whose place is the effect's —
/// the path compared by its end, since an effect records where `f.effect` was
/// called as the stack printed it — and, of those, on the ones of its name.
/// Two effects called on one line share a place, and their names tell them
/// apart; an effect whose name no node there has is on all of them, since a
/// node of a name given by an expression is named by its source. Several
/// nodes share a place and a name when a `finally` is drawn once for each
/// way out of its `try`; the effect is on them all. An effect without a place,
/// or at no node, is not on the graph.
///
/// Which calls an effect ran in, the session tells ([EffectCalls]): a node of
/// a function several calls reach — a graph several graphs call — is in each
/// of them, the effect in the one that called it. Pure.
library;

import 'dart:math';

import 'package:nanoflow_model/nanoflow_model.dart';

import 'session_feed.dart';

/// Whether an effect that ran at [effectPlace] is at the effect node at
/// [nodePlace]: the same place, or one that ends with it after a `/` (a
/// path the effect recorded from outside the project directory).
bool isPlaceOf(String effectPlace, String nodePlace) =>
    effectPlace == nodePlace || effectPlace.endsWith('/$nodePlace');

/// A call the code went through to come to an effect, and the function it
/// went to.
typedef CallStep = ({CallNode call, String function});

/// The calls the code goes through from the workflow's body to an effect,
/// outermost first: none for an effect of the workflow's own body.
typedef CallPath = List<CallStep>;

/// The effect nodes of a workflow's graph, and which of them an effect is on.
final class EffectPlaces {
  EffectPlaces._(this._workflow, this._functions, this.nodes);

  /// The effect nodes of [workflow] and of all it reaches in [functions]: the
  /// functions it calls, and so on; none without a [workflow].
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
  EffectCalls? _calls;

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

  /// The effect nodes [node] holds: an effect node itself; for a call, those
  /// of the bodies of its functions and of all they reach; none for a
  /// condition.
  Set<EffectNode> within(GraphNode node) => _within[node] ??= switch (node) {
    final EffectNode effect => {effect},
    ConditionNode() => const {},
    CallNode() => _inNode(node, const {}),
  };

  /// Whether [body] is that of a function the workflow calls: the code comes
  /// into it at each call, and may leave it and come into it again with no
  /// effect between. Not the workflow's own — drawn once whether it runs or
  /// calls itself.
  bool isCalled(GraphBody body) => switch (_owners[body]) {
    final owner? => owner != _workflow,
    null => false,
  };

  /// Whether [body] is the workflow's own: the code comes into it once.
  bool isWorkflow(GraphBody body) =>
      _workflow != null && identical(_functions[_workflow]?.body, body);

  /// The function of each body of the graph, by the body.
  late final Map<GraphBody, String> _owners = () {
    final owners = Map<GraphBody, String>.identity();
    for (final function in _functions.values) {
      owners[function.body] = function.id;
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

  /// The ways the code comes to [effect]: those into the body of the
  /// function its nodes are in, in the graph's order; none for an effect on
  /// no node.
  List<CallPath> waysTo(Effect? effect) => [
    for (final function in {for (final node in of(effect)) ?_functionOf[node]})
      ...?_ways[function],
  ];

  /// The calls [session]'s effects ran in: the one answer as long as the
  /// session does not change.
  EffectCalls callsIn(SessionData session) {
    final calls = _calls;
    if (calls != null &&
        identical(calls.session, session) &&
        calls._changes == session.changes) {
      return calls;
    }
    return _calls = EffectCalls._(this, session);
  }

  /// The ways the code comes into the body of each function the workflow
  /// reaches, by the function's id, in the graph's order: one with no calls
  /// into the workflow's own. A function is not entered again from inside
  /// itself: a recursive call holds nothing new.
  late final Map<String, List<CallPath>> _ways = () {
    final ways = <String, List<CallPath>>{};
    void enter(String id, CallPath way) {
      final function = _functions[id];
      if (function == null) return;
      (ways[id] ??= []).add(way);
      for (final node in function.body.nodes.whereType<CallNode>()) {
        for (final called in node.functions) {
          if (called == _workflow ||
              way.any((step) => step.function == called)) {
            continue;
          }
          enter(called, [...way, (call: node, function: called)]);
        }
      }
    }

    if (_workflow case final workflow?) enter(workflow, const []);
    return ways;
  }();

  /// The function whose body each effect node is in, by the node.
  late final Map<EffectNode, String> _functionOf = {
    for (final id in _ways.keys)
      for (final node in _functions[id]!.body.nodes.whereType<EffectNode>())
        node: id,
  };

  /// The effect nodes in [body] and all it reaches; a function in [entered]
  /// is not entered again: a recursive call holds nothing new.
  Set<EffectNode> _inBody(GraphBody body, Set<String> entered) => {
    for (final node in body.nodes) ..._inNode(node, entered),
  };

  Set<EffectNode> _inNode(GraphNode node, Set<String> entered) =>
      switch (node) {
        final EffectNode effect => {effect},
        ConditionNode() => const {},
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

/// Which calls of the graph a session's effects ran in. An effect whose
/// node the code comes to by one way ran in the calls of that way. One whose
/// node is in a function several calls reach — a graph several graphs call
/// — ran in those of the ways with the most calls first in common with the
/// ways of the effect it follows by `after`, the nearest on the graph: the
/// first effect of a call follows the effect before the call (spec §4.3).
/// When that tells no way from another — no effect to follow, or calls of one
/// function one after the other — the effect may have run in each.
final class EffectCalls {
  EffectCalls._(this.places, this.session) : _changes = session.changes;

  final EffectPlaces places;
  final SessionData session;

  /// [SessionData.changes] when the answers began: they hold until it moves.
  final int _changes;

  /// By the id of each effect looked at, its ways, or those of the nearest
  /// effect on the graph it follows; none without one.
  final Map<String, List<CallPath>> _carried = {};

  /// The ways [effect] may have run in, in the graph's order: the calls on
  /// each, outermost first; one when the journal tells which, none for an
  /// effect on no node.
  List<CallPath> waysOf(Effect? effect) =>
      effect == null || !places.onGraph(effect) ? const [] : _carry(effect);

  /// Whether [effect] ran on [node] or inside it: on an effect node of its
  /// place; in a call on its ways.
  bool isIn(Effect? effect, GraphNode node) => switch (node) {
    CallNode() => waysOf(
      effect,
    ).any((way) => way.any((step) => step.call == node)),
    _ => places.isIn(effect, node),
  };

  /// Whether [effect] ran in the body of the function [id] or in what it
  /// calls: in the workflow's, any effect on the graph; in another's, one
  /// with a way that goes to it.
  bool isInFunction(Effect? effect, String id) {
    final ways = waysOf(effect);
    return ways.isNotEmpty &&
        (id == places._workflow ||
            ways.any((way) => way.any((step) => step.function == id)));
  }

  List<CallPath> _carry(Effect effect) {
    // The effects whose ways wait for those of the effect before them, the
    // latest first: back to one known, one with a single way, or the first.
    final walked = <Effect>[];
    final seen = <String>{};
    List<CallPath> ways = const [];
    Effect? next = effect;
    while (next != null) {
      if (_carried[next.id] case final known?) {
        ways = known;
        break;
      }
      // A ring of `after`s, as reruns may leave.
      if (!seen.add(next.id)) break;
      walked.add(next);
      if (places.waysTo(next).length == 1) break;
      next = switch (next.after) {
        final key? => session.effectWithKey(key),
        null => null,
      };
    }
    for (final effect in walked.reversed) {
      final own = places.waysTo(effect);
      if (own.isNotEmpty) ways = _closest(own, ways);
      _carried[effect.id] = ways;
    }
    return ways;
  }

  /// Those of [ways] with the most calls first in common with one of
  /// [before]; all of them without [before].
  static List<CallPath> _closest(List<CallPath> ways, List<CallPath> before) {
    if (ways.length == 1 || before.isEmpty) return ways;
    int common(CallPath a, CallPath b) {
      var n = 0;
      while (n < a.length && n < b.length && a[n] == b[n]) {
        n++;
      }
      return n;
    }

    final scores = [
      for (final way in ways)
        before.map((other) => common(way, other)).reduce(max),
    ];
    final most = scores.reduce(max);
    return [
      for (final (i, way) in ways.indexed)
        if (scores[i] == most) way,
    ];
  }
}
