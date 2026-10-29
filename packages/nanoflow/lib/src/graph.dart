// A graph of nodes (graph node objects design): a node, made by `node`, is a
// unit of work that runs as one effect and knows neither what ran before it
// nor what runs after it; the graph says what follows what, by routes:
// functions of a node's output that call the next node with what it needs.
// It is the way to write a workflow: a graph runs as a session of a flow,
// and a graph may be a node of another graph.
//
// The graph is declared as a list of parts, each from a node or from a join
// with the route that follows it, checked as a whole when the graph is made,
// and built into a shape that `graph_run.dart` runs. The nodes a route leads
// to are found as the graph runs: no route is run before its node's output
// is there.

import 'dart:async';

import 'codecs.dart';
import 'flow.dart';
import 'graph_run.dart';

/// What a graph's part starts from and what a route leads to: a [Node] or a
/// [Graph].
sealed class Nodelike<I, O> {
  /// The name of its effect, or of the graph: different for each node of a
  /// graph.
  String get name;

  /// A [Next] that runs it with [input]: what a route gives. Runs nothing.
  Next call(I input);
}

/// A node of a graph: [body] runs as one effect named [name], whose result,
/// an [O], is journaled with the codec of [O]. A node that has not finished
/// when its process ends runs again whole when the session is resumed.
///
/// Made by [node], in a top-level variable; a node may be in several graphs.
final class Node<I, O> extends Nodelike<I, O> {
  Node._(this.name, this.body);

  @override
  final String name;

  /// The work of the node, to run it without a graph, as a test does.
  final FutureOr<O> Function(I input) body;

  @override
  Next call(I input) => Next._(this, input);

  /// [body] on [input], which is an [I]: cast here, where [I] is the node's
  /// own, as [body] read through a wider view of the node would throw.
  FutureOr<Object?> _runWith(Object? input) => body(input as I);

  TypeCodec _outputCodec(Codecs codecs) => codecs.of<O>();

  @override
  String toString() => 'Node($name)';
}

/// A node that runs [body] as an effect named [name]; the nodes of a graph
/// have different names.
///
/// ```dart
/// final inspect = node('inspect', (Change change) async => Report(...));
/// ```
Node<I, O> node<I, O>(String name, FutureOr<O> Function(I input) body) =>
    Node._(name, body);

/// What a route gives: [target] runs next, with [input]. Made by calling a
/// node or a graph, `inspect(change)`.
final class Next {
  Next._(this.target, this.input);

  final Nodelike<Object?, Object?> target;
  final Object? input;

  @override
  String toString() => 'Next(${target.name})';
}

/// A graph of nodes, a workflow: `flow.start(review, input)` runs it as a
/// session, and it may be a node of another graph.
///
/// ```dart
/// final review = Graph<String, void>('review', [
///   Graph.start(collect).next((collected) => switch (collected) {
///     Empty(:final branch) => discard(branch),
///     Found(:final change) => inspect(change),
///   }),
///   Graph.part(inspect).next((r) => r.findings.isEmpty
///       ? {publish(r), notify(r)}
///       : fix(r)),
///   Graph.part(fix).next((change) => inspect(change)),
///   Graph.join([publish, notify])
///       .next(((String, String) sent) => report(sent)),
/// ]);
/// ```
///
/// [I] is what the graph's starts take, [O] what it gives: the output that
/// went nowhere last.
final class Graph<I, O> extends Nodelike<I, O> {
  /// A graph named [name] — the name of its sessions and of the node it is in
  /// another graph, usually the name of its variable — of [parts].
  ///
  /// Throws an [ArgumentError] listing what makes [parts] no graph: no
  /// start; arrows of a node or a join declared twice; two nodes of one name;
  /// a join of fewer than 2, more than 6 or repeated nodes.
  Graph(this.name, List<Part<Object?>> parts) : _shape = _build(name, parts);

  @override
  final String name;

  final GraphShape _shape;

  /// A part from [node], a node the graph starts at: it takes the graph's
  /// input. A graph may have several starts, which start side by side.
  static Part<O> start<O>(Nodelike<Object?, O> node) =>
      Part._(_Head.start, [node]);

  /// A part from [node], any node.
  static Part<O> part<O>(Nodelike<Object?, O> node) =>
      Part._(_Head.part, [node]);

  /// A part from the join of [nodes], 2 to 6 different nodes: its route gets
  /// the record of their outputs, in this order, once each has given one,
  /// and declares its type, `((String, int) sent) => report(sent)`.
  static Part<Never> join(List<Nodelike<Object?, Object?>> nodes) =>
      Part._(_Head.join, nodes);

  @override
  Next call(I input) => Next._(this, input);

  /// Runs the graph with [input], which is an [I], in the session of [f]
  /// this is called in; gives the output that went nowhere last, `null`
  /// when none did.
  ///
  /// Throws what a node or a route threw, once the other branches have
  /// ended; a [TypeError] when that output is not an [O].
  Future<Object?> _runWith(Flow f, Object? input) async =>
      await runGraph(_shape, f, input as I) as O;

  @override
  String toString() => 'Graph($name)';
}

/// What the runner calls on a node, which the package does not export.
extension NodeRun on Node<Object?, Object?> {
  /// The node's body on [input].
  FutureOr<Object?> runWith(Object? input) => _runWith(input);

  /// How the node's output becomes JSON and comes back: the codec of its
  /// output type.
  TypeCodec outputCodec(Codecs codecs) => _outputCodec(codecs);
}

/// What the runner and the flow call on a graph, which the package does not
/// export: a graph runs only as a session of a flow, or as a node.
extension GraphRun on Graph<Object?, Object?> {
  /// Runs the graph with [input], an input of the graph, in the session of
  /// [f] this is called in; gives the output that went nowhere last.
  Future<Object?> runWith(Flow f, Object? input) => _runWith(f, input);
}

/// A part of a graph: a node or a join, and the route that follows it.
///
/// [O] is the output of the node; a join's is [Never], as its route
/// declares the type of the record it takes.
final class Part<O> {
  Part._(this._head, this._nodes, [this._routes = const []]);

  final _Head _head;

  /// The node it is from, or the nodes of its join.
  final List<Nodelike<Object?, Object?>> _nodes;

  /// The routes declared on it: one, unless it is declared twice.
  final List<Object? Function(Object? output)> _routes;

  /// The route from the part's node or join: once it has given an [output],
  /// [route] says what runs next, with what:
  ///
  /// - a [Next], `inspect(change)`: that node, with that input;
  /// - a set of them, `{publish(r), notify(r)}`: all of them, side by side;
  /// - `null`: nothing, the branch ends, and the output is the graph's
  ///   result.
  ///
  /// Anything else is a [StateError] of the graph as it runs. A route runs
  /// again on every resume, on the output from the journal, so it must give
  /// the same for the same output and change nothing in the world.
  ///
  /// A node's arrows are declared once: a part takes one route.
  Part<O> next(Object? Function(O output) route) => Part._(_head, _nodes, [
    ..._routes,
    // The route checks the type of what it takes as it is called: a join's
    // part, a Part<Never>, has nothing to cast to.
    (output) => (route as dynamic)(output),
  ]);
}

/// How a part starts.
enum _Head { start, part, join }

/// A graph as it runs: its nodes and what follows each.
final class GraphShape {
  GraphShape._(this.name);

  /// The name of the graph.
  final String name;

  /// The nodes the graph starts at, in order.
  final starts = <ShapeNode>[];

  /// The nodes known so far by their names.
  final _nodes = <String, ShapeNode>{};

  /// Every node known so far, in the order the graph first names it: the
  /// nodes of its parts, then those its routes have given as it ran.
  List<ShapeNode> get nodes => [..._nodes.values];

  /// The node of [node], made the first time it is asked for: as a route
  /// gives it.
  ///
  /// Throws a [StateError] when another node of the graph has its name.
  ShapeNode nodeFor(Nodelike<Object?, Object?> node) =>
      _nodeOrNull(node) ??
      (throw StateError('graph "$name": two nodes are named ${node.name}'));

  /// [nodeFor], or `null` when another node of the graph has its name.
  ShapeNode? _nodeOrNull(Nodelike<Object?, Object?> node) {
    final known = _nodes[node.name] ??= ShapeNode._(node);
    return identical(known.node, node) ? known : null;
  }
}

/// A node of a [GraphShape].
final class ShapeNode {
  ShapeNode._(this.node);

  /// The node or the graph.
  final Nodelike<Object?, Object?> node;

  /// Its name: the node's, or the graph's.
  String get name => node.name;

  /// What follows its output; `null` when it has no arrows.
  Object? Function(Object? output)? route;

  /// The joins it is one of the nodes of.
  final joins = <ShapeJoin>[];
}

/// A join: once each of its [sources] has given an output, its [route] gets
/// the record of them.
final class ShapeJoin {
  ShapeJoin._(this.sources);

  final List<ShapeNode> sources;

  /// What follows the record; `null` when it has no arrows.
  Object? Function(Object? record)? route;

  /// What the join is called in a graph's errors.
  String get name => 'the join of ${sources.map((s) => s.name).join(', ')}';
}

/// The shape [graph] runs as.
GraphShape shapeOf(Graph<Object?, Object?> graph) => graph._shape;

/// The shape of the graph [name] of [parts].
GraphShape _build(String name, List<Part<Object?>> parts) {
  final shape = GraphShape._(name);
  // A set: a problem met twice is listed once.
  final problems = <String>{};

  ShapeNode? node(Nodelike<Object?, Object?> given) {
    final made = shape._nodeOrNull(given);
    if (made == null) problems.add('two nodes are named ${given.name}');
    return made;
  }

  var startsDeclared = false;
  for (final Part(:_head, :_nodes, :_routes) in parts) {
    switch (_head) {
      case _Head.start || _Head.part:
        final at = node(_nodes.single);
        if (_head == _Head.start) {
          startsDeclared = true;
          if (at != null) shape.starts.add(at);
        }
        if (at == null || _routes.isEmpty) continue;
        if (_routes.length > 1 || at.route != null) {
          problems.add('the arrows of ${at.name} are declared twice');
        } else {
          at.route = _routes.single;
        }
      case _Head.join:
        final sources = [for (final source in _nodes) node(source)];
        if (sources.length < 2 ||
            sources.length > 6 ||
            _nodes.toSet().length != sources.length) {
          problems.add('a join takes 2 to 6 different nodes');
          continue;
        }
        if (sources.contains(null)) continue;
        final join = ShapeJoin._(sources.cast());
        for (final source in join.sources) {
          source.joins.add(join);
        }
        if (_routes.length > 1) {
          problems.add('the arrows of ${join.name} are declared twice');
        } else {
          join.route = _routes.singleOrNull;
        }
    }
  }

  if (!startsDeclared) problems.add('the graph has no start');
  if (problems.isNotEmpty) {
    throw ArgumentError('graph "$name":\n- ${problems.join('\n- ')}');
  }
  return shape;
}
