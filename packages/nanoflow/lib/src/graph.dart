// A graph of nodes (graph design): a node is a function from an input to an
// output that knows neither what ran before it nor what runs after it; the
// graph says what follows what. It is the other way to write a workflow, beside
// the workflow function, and the two nest: a node may be a workflow function
// or another graph, and a workflow function may call a graph.
//
// The graph is declared as a list of parts, each an arrow or a chain of
// arrows from a node or from a join, checked as a whole when the graph is
// made, and built into a shape that `graph_run.dart` runs.

import 'flow.dart';
import 'graph_run.dart';
import 'project.dart';

/// An output with a payload: a node that ends in one of several ways returns
/// one of its subclasses, and a map of targets keyed by the subclass gives its
/// target the [value] (graph design §5).
///
/// ```dart
/// sealed class Collected {}
/// final class Empty extends Exit<void> implements Collected { Empty() : super(null); }
/// final class Found extends Exit<Change> implements Collected { Found(super.value); }
/// ```
abstract class Exit<T> {
  const Exit(this.value);

  /// What the target of the exit gets.
  final T value;
}

/// A graph of nodes, a workflow of its own: `flow.start(review.call, input)`
/// runs it as a session, a workflow function calls it as `review(f, input)`,
/// and it may be a node of another graph.
///
/// ```dart
/// final review = Graph<String, void>('review', [
///   Graph.start(collect).next({Empty: discard, Found: inspect}),
///   Graph.part(inspect).next({Clean: {publish, notify}, Findings: fix}),
///   Graph.part(fix).next(inspect),
///   Graph.join([publish, notify]).next(report),
/// ]);
/// ```
///
/// A node is a top-level function or a static method of one parameter, which
/// runs as an effect named after it; a workflow function of a [Flow] and an
/// input, which runs as it is; or a graph. [I] is what the graph's starts
/// take, [O] what it gives: the output that went nowhere last.
final class Graph<I, O> {
  /// A graph named [name] — the name of its sessions and of the node it is in
  /// another graph, usually the name of its variable — of [parts].
  ///
  /// Throws an [ArgumentError] listing what makes [parts] no graph: a node
  /// that is not one, or whose name cannot be found; two nodes of one name;
  /// arrows of a node declared twice; no start; a node that cannot be
  /// reached; a join of fewer than 2, more than 6 or repeated nodes; a map
  /// after a join; `otherwise` without a map; `next` after a set or a map; an
  /// empty set of targets.
  Graph(this.name, List<Part> parts) : _shape = _build(name, parts) {
    _graphs.add(this);
  }

  /// The name of the graph.
  final String name;

  final GraphShape _shape;

  /// A part from [node], a node the graph starts at: it takes the graph's
  /// input. A graph may have several starts, which start side by side.
  static Part start(Object node) => Part._head(_Chain(_Head.start, [node]));

  /// A part from [node], any node.
  static Part part(Object node) => Part._head(_Chain(_Head.part, [node]));

  /// A part from the join of [nodes], 2 to 6 different nodes: its target
  /// gets the record of their outputs, in this order, once each has given
  /// one.
  static Part join(List<Object> nodes) => Part._head(_Chain(_Head.join, nodes));

  /// Runs the graph with [input] in the session of [f] this is called in;
  /// gives the output that went nowhere last, `null` when none did.
  ///
  /// Throws what a node threw, once the other branches have ended.
  Future<O> call(Flow f, I input) async =>
      await runGraph(_shape, f, input) as O;

  @override
  String toString() => 'Graph($name)';
}

/// A part of a graph: where a chain of arrows is.
///
/// [next] adds arrows from the node the part is at; the part goes on at the
/// target when it is one node, and ends at a set or a map of targets.
final class Part {
  Part._(this._chain, this._at);

  Part._head(_Chain chain)
    : this._(chain, chain.kind == _Head.join ? chain : chain.nodes.single);

  final _Chain _chain;

  /// The node the part is at, its chain for a join, or `null` after a set or
  /// a map.
  final Object? _at;

  /// Arrows from the node the part is at to [target]:
  ///
  /// - a node, which gets the output as it is;
  /// - a set of nodes, which all get it, side by side;
  /// - a map of keys to targets, each a node or a set of nodes: of the output
  ///   `v`, a record `(k, p)` is matched by `k` and gives `p`, an [Exit] is
  ///   matched by itself and gives its value, anything else is matched by
  ///   itself and gives itself; a key that is a type matches when the
  ///   runtime type is exactly it, any other key when it is `==`. The first
  ///   key that matches gives its targets what it gives; when none does, the
  ///   targets of [otherwise] get the output as it is, and without them the
  ///   branch ends.
  ///
  /// A node's arrows are declared once.
  Part next(Object target, {Object? otherwise}) {
    final at = _at;
    if (at == null) {
      _chain.problems.add('next after a set or a map of targets');
      return this;
    }
    _chain.arrows.add((from: at, target: target, otherwise: otherwise));
    return Part._(_chain, target is Set || target is Map ? null : target);
  }
}

/// How a chain of arrows starts.
enum _Head { start, part, join }

/// The arrows of a part from its head on.
final class _Chain {
  _Chain(this.kind, this.nodes);

  final _Head kind;

  /// The node it starts from, or the nodes of its join.
  final List<Object> nodes;

  /// The arrows: from a node, or from this chain for its join.
  final arrows = <({Object from, Object target, Object? otherwise})>[];

  /// What [Part.next] found wrong.
  final problems = <String>[];
}

/// The graphs made so far, which [graphOfCall] looks in.
final _graphs = <Graph<Object?, Object?>>[];

/// The graph whose `call` [function] is: what `flow.start(review, …)` is
/// given for a graph; `null` for any other function.
Graph<Object?, Object?>? graphOfCall(Function function) {
  for (final graph in _graphs) {
    if (graph.call == function) return graph;
  }
  return null;
}

/// What a node is.
enum NodeKind {
  /// A function of one parameter: it runs as an effect.
  function,

  /// A workflow function of a [Flow] and an input: it runs as it is.
  workflow,

  /// A graph: it runs as it is.
  graph,
}

/// A graph as it runs: its nodes and what follows each.
final class GraphShape {
  GraphShape._(this.name, this.starts, this.nodes);

  /// The name of the graph.
  final String name;

  /// The nodes the graph starts at, in order.
  final List<ShapeNode> starts;

  /// Every node, in the order the graph first names it.
  final List<ShapeNode> nodes;
}

/// A node of a [GraphShape].
final class ShapeNode {
  ShapeNode._(this.node, this.name, this.kind);

  /// The function or the graph.
  final Object node;

  /// Its name: the function's, or the graph's.
  final String name;

  final NodeKind kind;

  /// Where its output goes; `null` when it has no arrows.
  Routes? routes;

  /// The joins it is one of the nodes of.
  final joins = <ShapeJoin>[];
}

/// Where the output of a node goes.
sealed class Routes {
  const Routes();
}

/// Every target gets the output as it is.
final class AllRoutes extends Routes {
  const AllRoutes(this.targets);

  final List<ShapeNode> targets;
}

/// The targets of the first key the output matches get what it gives, the
/// [otherwise] targets the output when none does.
final class CaseRoutes extends Routes {
  const CaseRoutes(this.cases, this.otherwise);

  final List<({Object? key, List<ShapeNode> targets})> cases;
  final List<ShapeNode> otherwise;
}

/// A join: once each of its [sources] has given an output, its [targets]
/// get the record of them.
final class ShapeJoin {
  ShapeJoin._(this.sources);

  final List<ShapeNode> sources;
  List<ShapeNode> targets = const [];
}

/// The shape [graph] runs as.
GraphShape shapeOf(Graph<Object?, Object?> graph) => graph._shape;

/// What [value] is as a node; `null` when it is none.
NodeKind? _kindOf(Object? value) {
  if (value is Graph<Object?, Object?>) return NodeKind.graph;
  if (value is Object? Function(Flow, Never)) return NodeKind.workflow;
  if (value is Object? Function(Never)) return NodeKind.function;
  return null;
}

/// The shape of the graph [name] of [parts].
GraphShape _build(String name, List<Part> parts) {
  final problems = <String>[];
  final nodes = <Object, ShapeNode>{};
  final named = <String, ShapeNode>{};
  final refused = <Object?>{};

  ShapeNode? node(Object? given) {
    // The call of a graph, as flow.start takes it, is the graph.
    final value = given is Function ? graphOfCall(given) ?? given : given;
    if (nodes[value] case final known?) return known;
    if (refused.contains(value)) return null;
    String? problem;
    ShapeNode? made;
    switch ((_kindOf(value), value)) {
      case (null, _):
        problem =
            '$value is not a node: a node is a function of one parameter, '
            'a workflow function of a Flow and an input, or a Graph';
      case (final kind?, final Graph<Object?, Object?> graph):
        made = ShapeNode._(graph, graph.name, kind);
      case (final kind?, final Function function):
        final functionName = staticNameOf(function);
        if (functionName == null) {
          problem =
              '$function: a node is a top-level function or a static '
              'method: the name of anything else cannot be found';
        } else {
          made = ShapeNode._(function, functionName, kind);
        }
      case _:
    }
    if (made != null && named.containsKey(made.name)) {
      problem = 'two nodes are named ${made.name}';
      made = null;
    }
    if (made == null) {
      problems.add(problem!);
      refused.add(value);
      return null;
    }
    named[made.name] = nodes[value!] = made;
    return made;
  }

  /// The nodes of [target], a node or a set of nodes; `null` when it is
  /// neither.
  List<ShapeNode>? targetsOf(Object? target) {
    if (target is Set) {
      if (target.isEmpty) problems.add('a set of targets is empty');
      final targets = [for (final element in target) node(element)];
      return targets.contains(null) ? null : targets.cast();
    }
    final single = node(target);
    return single == null ? null : [single];
  }

  final starts = <ShapeNode>[];
  var startsDeclared = false;
  final joins = <_Chain, ShapeJoin>{};
  final routed = <Object>{};
  for (final Part(:_chain) in parts) {
    problems.addAll(_chain.problems);
    switch (_chain.kind) {
      case _Head.start:
        startsDeclared = true;
        if (node(_chain.nodes.single) case final start?) starts.add(start);
      case _Head.part:
        node(_chain.nodes.single);
      case _Head.join:
        final sources = [for (final source in _chain.nodes) node(source)];
        if (sources.length < 2 ||
            sources.length > 6 ||
            _chain.nodes.toSet().length != sources.length) {
          problems.add('a join takes 2 to 6 different nodes');
        } else if (!sources.contains(null)) {
          final join = joins[_chain] = ShapeJoin._(sources.cast());
          for (final source in join.sources) {
            source.joins.add(join);
          }
        }
    }
    for (final (:from, :target, :otherwise) in _chain.arrows) {
      final source = from is _Chain ? null : node(from);
      final what = from is _Chain ? 'the join' : source?.name;
      if (what == null) continue;
      if (!routed.add(from)) {
        problems.add('the arrows of $what are declared twice');
        continue;
      }
      if (otherwise != null && target is! Map) {
        problems.add('otherwise goes with a map');
        continue;
      }
      if (from is _Chain) {
        if (target is Map) {
          problems.add('a join leads to a node or a set');
        } else if (joins[from] case final join?) {
          join.targets = targetsOf(target) ?? const [];
        }
        continue;
      }
      source!.routes = switch (target) {
        Map() => CaseRoutes([
          for (final MapEntry(:key, :value) in target.entries)
            (key: key, targets: targetsOf(value) ?? const []),
        ], otherwise == null ? const [] : targetsOf(otherwise) ?? const []),
        _ => AllRoutes(targetsOf(target) ?? const []),
      };
    }
  }

  if (!startsDeclared) problems.add('the graph has no start');
  final reached = <ShapeNode>{};
  final queue = <ShapeNode>[];
  void reach(ShapeNode node) {
    if (reached.add(node)) queue.add(node);
  }

  starts.forEach(reach);
  while (queue.isNotEmpty) {
    final at = queue.removeLast();
    switch (at.routes) {
      case AllRoutes(:final targets):
        targets.forEach(reach);
      case CaseRoutes(:final cases, :final otherwise):
        for (final (key: _, :targets) in cases) {
          targets.forEach(reach);
        }
        otherwise.forEach(reach);
      case null:
    }
    for (final join in at.joins) {
      if (join.sources.every(reached.contains)) join.targets.forEach(reach);
    }
  }
  for (final node in nodes.values) {
    if (!reached.contains(node)) problems.add('${node.name} cannot be reached');
  }

  if (problems.isNotEmpty) {
    throw ArgumentError('graph "$name":\n- ${problems.join('\n- ')}');
  }
  return GraphShape._(name, starts, nodes.values.toList());
}
