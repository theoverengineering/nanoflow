// A graph of nodes (graph node objects design): a node, made by `node`, is a
// unit of work that runs as one effect and knows neither what ran before it
// nor what runs after it; the graph says what follows what, by routes:
// functions of a node's output that call the next node with what it needs.
// It is the way to write a workflow: a graph runs as a session of a flow,
// and a graph may be a node of another graph.
//
// The graph is declared as a list of parts, each from a node or from a join
// with the route that follows it — and for a node, the route that follows its
// failure (failure.dart) —, checked as a whole when the graph is made,
// and built into a shape that `graph_run.dart` runs. The nodes a route leads
// to are found as the graph runs: no route is run before its node's output
// is there.

import 'dart:async';
import 'dart:collection';

import 'call_limit.dart';
import 'codecs.dart';
import 'failure.dart';
import 'flow.dart';
import 'graph_run.dart';

/// What a graph's part starts from and what a route leads to: a [Node] or a
/// [Graph].
sealed class Nodelike<I, O> {
  /// The name of its effect, or of the graph: different for each node of a
  /// graph.
  String get name;

  /// A [Next] that runs it with [input]: what a route gives. Runs nothing.
  ///
  /// With a [limit], no more copies of this call run at once — those the
  /// route of the same node or join gives it in the same run of the graph,
  /// on every round of a loop —; the others wait, in the order they were
  /// called, and write nothing until they run. A copy is the run of what is
  /// called: a node's effect, or all of a graph's nodes. Throws an
  /// [ArgumentError] when [limit] is less than 1.
  Next call(I input, {int? limit});
}

/// A node of a graph: [body] runs as one effect named [name], whose result,
/// an [O], is journaled with the codec of [O]. A node that has not finished
/// when its process ends runs again whole when the session is resumed.
///
/// Made by [node], in a top-level variable; a node may be in several graphs.
final class Node<I, O> extends Nodelike<I, O> {
  Node._(this.name, this.body, this.concurrency)
    : _slots = concurrency == null ? null : Slots(concurrency);

  @override
  final String name;

  /// The work of the node, to run it without a graph, as a test does.
  final FutureOr<O> Function(I input) body;

  /// How many effects of the node run at once in the process, whichever
  /// sessions and graphs they are of; the others wait, in the order they were
  /// called, and write nothing until they run. `null` for no limit.
  final int? concurrency;

  final Slots? _slots;

  @override
  Next call(I input, {int? limit}) => Next._(this, input, limit);

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
///
/// With a [concurrency], no more of the node's effects run at once in the
/// process; a node run once per item of a hundred then does not start a
/// hundred at a time:
///
/// ```dart
/// final compress = node('compress', body, concurrency: 4);
/// ```
///
/// Throws an [ArgumentError] when [concurrency] is less than 1.
Node<I, O> node<I, O>(
  String name,
  FutureOr<O> Function(I input) body, {
  int? concurrency,
}) {
  if (concurrency != null && concurrency < 1) {
    throw ArgumentError.value(concurrency, 'concurrency', 'must be 1 or more');
  }
  return Node._(name, body, concurrency);
}

/// The slots of a node with a concurrency: [take] one before the effect
/// starts and [release] it after, so no more than `count` are taken at once.
/// Those waiting are given a slot in the order they asked.
final class Slots {
  Slots(this.count);

  final int count;
  int _taken = 0;
  final Queue<Completer<void>> _waiting = Queue();

  /// Completes once a slot is the caller's.
  Future<void> take() {
    if (_taken < count) {
      _taken++;
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    return waiter.future;
  }

  /// Gives the slot back: to the first waiting, when there is one.
  void release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _taken--;
    }
  }
}

/// What a route gives: [target] runs next, with [input]. Made by calling a
/// node or a graph, `inspect(change)`, `developIdea(idea, limit: 2)`.
final class Next {
  Next._(this.target, this.input, this.limit) {
    if (limit case final limit? when limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'must be 1 or more');
    }
  }

  final Nodelike<Object?, Object?> target;
  final Object? input;

  /// How many copies of this call run at once, at most (see
  /// [Nodelike.call]); `null` for no limit.
  final int? limit;

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
/// A part of a node may say what follows when the node fails:
///
/// ```dart
/// Graph.part(developIdea)
///     .next((developed) => settle(developed))
///     .failed((request, failure) => giveBack((request, failure.error))),
/// ```
///
/// [I] is what the graph's starts take, [O] what it gives: the output that
/// went nowhere last.
final class Graph<I, O> extends Nodelike<I, O> {
  /// A graph named [name] — the name of its sessions and of the node it is in
  /// another graph, usually the name of its variable — of [parts].
  ///
  /// Throws an [ArgumentError] listing what makes [parts] no graph: no
  /// start; arrows of a node or a join, or the failure route of a node,
  /// declared twice; a failure route of a join; two nodes of one name; a
  /// join of fewer than 2, more than 6 or repeated nodes.
  Graph(this.name, List<Part<Object?, Object?>> parts)
    : _shape = _build(name, parts);

  @override
  final String name;

  final GraphShape _shape;

  /// A part from [node], a node the graph starts at: it takes the graph's
  /// input. A graph may have several starts, which start side by side.
  static Part<I, O> start<I, O>(Nodelike<I, O> node) =>
      Part._(_Head.start, [node]);

  /// A part from [node], any node.
  static Part<I, O> part<I, O>(Nodelike<I, O> node) =>
      Part._(_Head.part, [node]);

  /// A part from the join of [nodes], 2 to 6 different nodes: its route gets
  /// the record of their outputs, in this order, once each has given one,
  /// and declares its type, `((String, int) sent) => report(sent)`. A join
  /// calls nothing, and has no failure route.
  static Part<Never, Never> join(List<Nodelike<Object?, Object?>> nodes) =>
      Part._(_Head.join, nodes);

  @override
  Next call(I input, {int? limit}) => Next._(this, input, limit);

  /// Runs the graph with [input], which is an [I], in the session of [f]
  /// this is called in, as a part of [copies]; gives the output that went
  /// nowhere last, `null` when none did.
  ///
  /// Throws what a node or a route threw, once the other branches have
  /// ended; a [TypeError] when that output is not an [O]. With [failures]
  /// [Failures.caught], gives such a failure as a [Caught] instead.
  Future<Object?> _runWith(
    Flow f,
    Object? input,
    List<CallCopy> copies,
    Failures failures,
  ) async => await runGraph(
    _shape,
    f,
    input as I,
    copies: copies,
    failures: failures,
    output: (output) => output as O,
  );

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

  /// The node's slots; `null` when it has no concurrency.
  Slots? get slots => _slots;
}

/// What the runner and the flow call on a graph, which the package does not
/// export: a graph runs only as a session of a flow, or as a node.
extension GraphRun on Graph<Object?, Object?> {
  /// Runs the graph with [input], an input of the graph, in the session of
  /// [f] this is called in; gives the output that went nowhere last.
  ///
  /// [copies] are the copies of calls with a limit the run is a part of,
  /// the outermost first: each of its effects takes their slots before it
  /// is written. [failures] says what its failure comes to: whether a
  /// failure route catches it, round the call or at it.
  Future<Object?> runWith(
    Flow f,
    Object? input, {
    List<CallCopy> copies = const [],
    Failures failures = Failures.thrown,
  }) => _runWith(f, input, copies, failures);
}

/// A part of a graph: a node or a join, the route that follows it, and for
/// a node the route that follows its failure.
///
/// [I] is the input of the node, [O] its output; a join's are [Never], as
/// its route declares the type of the record it takes.
final class Part<I, O> {
  Part._(
    this._head,
    this._nodes, [
    this._routes = const [],
    this._failed = const [],
  ]);

  final _Head _head;

  /// The node it is from, or the nodes of its join.
  final List<Nodelike<Object?, Object?>> _nodes;

  /// The routes declared on it: one, unless it is declared twice.
  final List<Object? Function(Object? output)> _routes;

  /// The failure routes declared on it: one, unless it is declared twice.
  final List<FailureRoute> _failed;

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
  Part<I, O> next(Object? Function(O output) route) => Part._(_head, _nodes, [
    ..._routes,
    // The route checks the type of what it takes as it is called: a
    // join's part, a Part<Never, Never>, has nothing to cast to.
    (output) => (route as dynamic)(output),
  ], _failed);

  /// The route from the failure of the part's node: once a call of the
  /// node has failed — the node threw; for a graph, a node or a route of it
  /// threw that nothing in it caught, once its other branches have ended —,
  /// [route] gets the [input] of that call and the [CallFailure] and says
  /// what runs next, as [next]'s route does; `null` ends the branch, and
  /// as the call gave no output, nothing goes to the graph's result.
  ///
  /// The failure fails neither the branch nor the session, and is final:
  /// on resume, the node that failed — of the graph, any node that failed in
  /// it — does not run again, and [route] gets the same failure from the
  /// journal. A stop of the flow, or the end of the session by a failure of
  /// its store or a codec, is no failure: no route catches it.
  ///
  /// A node's failure route is declared once; a join has none.
  Part<I, O> failed(Object? Function(I input, CallFailure failure) route) =>
      Part._(_head, _nodes, _routes, [
        ..._failed,
        (input, failure) => route(input as I, failure),
      ]);
}

/// A route from the failure of a call: its input and the failure give what
/// runs next.
typedef FailureRoute = Object? Function(Object? input, CallFailure failure);

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

  /// What follows the failure of a call of it; `null` when it has no
  /// failure route: its failure fails the branch.
  FailureRoute? failed;

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
GraphShape _build(String name, List<Part<Object?, Object?>> parts) {
  final shape = GraphShape._(name);
  // A set: a problem met twice is listed once.
  final problems = <String>{};

  ShapeNode? node(Nodelike<Object?, Object?> given) {
    final made = shape._nodeOrNull(given);
    if (made == null) problems.add('two nodes are named ${given.name}');
    return made;
  }

  var startsDeclared = false;
  for (final Part(:_head, :_nodes, :_routes, :_failed) in parts) {
    switch (_head) {
      case _Head.start || _Head.part:
        final at = node(_nodes.single);
        if (_head == _Head.start) {
          startsDeclared = true;
          if (at != null) shape.starts.add(at);
        }
        if (at == null) continue;
        if (_routes.isNotEmpty) {
          if (_routes.length > 1 || at.route != null) {
            problems.add('the arrows of ${at.name} are declared twice');
          } else {
            at.route = _routes.single;
          }
        }
        if (_failed.isNotEmpty) {
          if (_failed.length > 1 || at.failed != null) {
            problems.add('the failure route of ${at.name} is declared twice');
          } else {
            at.failed = _failed.single;
          }
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
        if (_failed.isNotEmpty) {
          problems.add(
            '${join.name} has a failure route: a join calls nothing',
          );
        }
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
