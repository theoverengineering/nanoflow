import 'dart:async';

/// A node of any kind that takes data as [F], `void Function(In)`.
///
/// [F] is a function type because parameters of functions are
/// contravariant: a node that takes `Object?` fits wherever any data goes,
/// while type arguments of classes would make it the other way round.
///
/// A node is a collection of itself: a parameter `Iterable<AnyVertex<…>>`
/// takes one node and a set of nodes alike. A worker and a fork that take the
/// same data have this type in common, so a set of both is a set of
/// `AnyVertex` rather than of `Object`.
sealed class AnyVertex<F> extends Iterable<AnyVertex<F>> {
  @override
  Iterator<AnyVertex<F>> get iterator => [this].iterator;
}

/// A node of a graph: a [Worker] or a [Fork].
///
/// [Self] is the node's own type, so that a part knows whether it is at a
/// worker or at a fork.
sealed class Vertex<F, Self> extends AnyVertex<F> {
  Vertex._(this._input, this._inputTakesNull, this._call);

  final Type _input;

  /// Whether [_input] is nullable: its mirror does not say.
  final bool _inputTakesNull;

  final FutureOr<Object?> Function(Object? input) _call;
}

/// Nodes that take data of type [T]: one node or a set of nodes.
typedef Accepts<T> = Iterable<AnyVertex<void Function(T)>>;

/// A worker node: it does its work and passes on what it returns, an [O].
final class Worker<F, O> extends Vertex<F, Worker<F, O>> {
  Worker._(
    super._input,
    super._inputTakesNull,
    this._output,
    this._outputTakesNull,
    super._call,
  ) : super._();

  final Type _output;
  final bool _outputTakesNull;

  @override
  String toString() => 'node(${inputTypeOf(this)} → $_output)';
}

/// A fork: it decides where the run goes by its outcome, an [R].
final class Fork<F, R> extends Vertex<F, Fork<F, R>> {
  Fork._(super._input, super._inputTakesNull, this._outcome, super._call)
    : super._();

  final Type _outcome;

  @override
  String toString() => 'fork(${inputTypeOf(this)} → $_outcome)';
}

/// A worker node that does [work]; the function is not called here.
///
/// The parameter type of [work] is the node's `in`, its result type the
/// node's `out`.
Worker<void Function(I), O> node<I, O>(FutureOr<O> Function(I) work) =>
    Worker._(I, null is I, O, null is O, (input) => work(input as I));

/// A fork that calls [decide] to get the outcome; the function is not called
/// here.
///
/// The parameter type of [decide] is the fork's `in`. A `bool` outcome makes
/// an if, any other type a switch.
Fork<void Function(I), R> fork<I, R>(FutureOr<R> Function(I) decide) =>
    Fork._(I, null is I, R, (input) => decide(input as I));

/// [vertex] as the node it is: every [AnyVertex] is a [Vertex].
Vertex<Object?, Object?> asVertex(AnyVertex<Object?> vertex) =>
    switch (vertex) {
      Vertex<Object?, Object?>() => vertex,
    };

/// The type of data [vertex] takes: the parameter type of its function.
Type inputTypeOf(Vertex<Object?, Object?> vertex) => vertex._input;

/// Whether the type of data [vertex] takes is nullable, such as `Report?`
/// or `Object?`: its mirror does not say.
bool inputTakesNull(Vertex<Object?, Object?> vertex) => vertex._inputTakesNull;

/// The type [worker]'s function returns, as `node` was given it: an
/// asynchronous function returning `Future<Change>` gives `Change`.
Type outputTypeOf(Worker<Object?, Object?> worker) => worker._output;

/// Whether the type [worker]'s function returns is nullable.
bool outputTakesNull(Worker<Object?, Object?> worker) =>
    worker._outputTakesNull;

/// The type of [fork]'s outcome.
Type outcomeTypeOf(Fork<Object?, Object?> fork) => fork._outcome;

/// Calls the function of [vertex] with [input], a value of its input type.
FutureOr<Object?> callVertex(Vertex<Object?, Object?> vertex, Object? input) =>
    vertex._call(input);
