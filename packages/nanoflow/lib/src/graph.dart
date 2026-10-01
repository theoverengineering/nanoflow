import 'vertex.dart';

/// A graph: parts — flat chains of arrows — in any order.
///
/// [S] is `void Function(In)`, where `In` is the type of data the start nodes
/// take.
sealed class Graph<S> {
  /// Collects [parts] into one graph.
  factory Graph(List<Part<S, Object?>> parts) = _Parts<S>;

  /// Starts a part at [node], a node runs start from.
  static Part<F, T> start<F, T>(Vertex<F, T> node) =>
      Part._(Chain._(node, isStart: true), node as T);

  /// Starts a part at [node], any node.
  static Part<void Function(Object?), T> part<T>(Vertex<Object?, T> node) =>
      Part._(Chain._(node, isStart: false), node as T);
}

final class _Parts<S> implements Graph<S> {
  _Parts(List<Part<S, Object?>> parts) : parts = List.unmodifiable(parts);

  final List<Part<S, Object?>> parts;
}

/// A part of a graph, at a node or at a set of nodes ([T]).
///
/// A part at a worker goes on with `.next`; a part at a fork stays there
/// with `.then` and `.otherwise`; a part at a set of nodes ends.
final class Part<S, T> implements Graph<S> {
  Part._(this._chain, this._at);

  /// The chain this part belongs to: each part continuing it shares it.
  final Chain _chain;

  /// Where the part is.
  final T _at;
}

/// How [WorkerPart.next] goes on from a worker that returns [O].
extension WorkerPart<S, I, O> on Part<S, Worker<void Function(I), O>> {
  /// An arrow to [target], a node or a set of nodes that take an [O]; the
  /// part goes on at [target].
  Part<S, T> next<T extends Accepts<O>>(T target) {
    _chain._add(_at, const NextExit(), target);
    return Part._(_chain, target);
  }
}

/// Where an if — a fork with a `bool` outcome — sends the run.
extension IfPart<S, I> on Part<S, Fork<void Function(I), bool>> {
  /// Where the run goes when the outcome is `true`.
  Part<S, Fork<void Function(I), bool>> then(Accepts<I> target) {
    _chain._add(_at, const OutcomeExit(true), target);
    return this;
  }

  /// Where the run goes when the outcome is `false`.
  Part<S, Fork<void Function(I), bool>> otherwise(Accepts<I> target) {
    _chain._add(_at, const OtherwiseExit(), target);
    return this;
  }
}

/// Where a switch — a fork with an outcome of any other type — sends the
/// run.
extension SwitchPart<S, I, R> on Part<S, Fork<void Function(I), R>> {
  /// Where the run goes for each outcome.
  Part<S, Fork<void Function(I), R>> then(Map<R, Accepts<I>> targets) {
    for (final MapEntry(:key, :value) in targets.entries) {
      _chain._add(_at, OutcomeExit(key), value);
    }
    return this;
  }

  /// Where the run goes when the outcome matches no key of `then`.
  Part<S, Fork<void Function(I), R>> otherwise(Accepts<I> target) {
    _chain._add(_at, const OtherwiseExit(), target);
    return this;
  }
}

/// A part from its start, with every arrow declared along it.
final class Chain {
  Chain._(this.head, {required this.isStart});

  /// The node the part starts at.
  final Vertex<Object?, Object?> head;

  /// Whether the part was started with `Graph.start`.
  final bool isStart;

  /// The arrows in the order they were declared.
  List<Arrow> get arrows => List.unmodifiable(_arrows);
  final List<Arrow> _arrows = [];

  void _add(
    Vertex<Object?, Object?> from,
    Exit exit,
    Iterable<AnyVertex<Object?>> target,
  ) => _arrows.add(
    Arrow(
      from: from,
      exit: exit,
      single: target is Vertex<Object?, Object?> ? target : null,
      targets: List.unmodifiable(target.map(asVertex)),
    ),
  );
}

/// An exit of a node declared in a part, and where it leads.
final class Arrow {
  Arrow({
    required this.from,
    required this.exit,
    required this.single,
    required this.targets,
  });

  final Vertex<Object?, Object?> from;
  final Exit exit;

  /// The target when it is one node rather than a set.
  final Vertex<Object?, Object?>? single;

  /// The target's nodes: the one node, or the set's nodes in set order.
  final List<Vertex<Object?, Object?>> targets;
}

/// Which exit of a node an arrow declares.
sealed class Exit {
  const Exit();
}

/// The `next` of a worker.
final class NextExit extends Exit {
  const NextExit();
}

/// The `then` of a fork for one outcome: `true` for an if.
final class OutcomeExit extends Exit {
  const OutcomeExit(this.outcome);

  final Object? outcome;
}

/// The `otherwise` of a fork.
final class OtherwiseExit extends Exit {
  const OtherwiseExit();
}

/// The chains of [graph], each once, in the order of its parts.
List<Chain> chainsOf(Graph<Object?> graph) {
  final parts = switch (graph) {
    _Parts(:final parts) => parts,
    Part() => [graph],
  };
  final chains = <Chain>[];
  for (final part in parts) {
    if (!chains.any((c) => identical(c, part._chain))) chains.add(part._chain);
  }
  return chains;
}
