// Runs a graph's shape in the session it is called in (graph node objects
// design §4–§7).
//
// The graph is run by code that awaits its nodes as a hand-written workflow
// function would: a branch awaits a node — a node is an effect, a graph runs
// its own nodes —, calls its route on the output, goes on in place while one
// node follows, and starts the nodes that follow side by side with
// `Future.wait` when several do. So the effects of a graph get keys and
// `after`s as those of a function do: the same on every run, whatever the
// timing (spec §4.3); and a route runs again on resume, on the output from
// the journal.
//
// A join goes on from the branch of its first node, once every other node of
// it has given an output: its route so leads on in the context of the first
// node's effect, whichever node gave its output last. A join that never
// fills up would hold its branch for ever; once no branch runs, nothing can
// fill it any more, and the branches waiting at joins end.
//
// A call a route gives with a limit is a copy of its call site in the run
// (call_limit.dart), made as the route gives it, in order, and ended once
// what it called has ended; the effects of what it called take its slot
// before they are written, outside the session's zone, so the branch awaits
// the node as it does without a limit, and its effects get the same keys.
//
// A call of a node with a failure route (failure.dart) gives its failure as
// a [Caught] instead of an output, and the branch goes on along the failure
// route from where it would have gone on from the output. In a run whose
// failure a failure route catches, a branch that fails does not throw: the
// run keeps its failure, with the place of the branch in the graph's order,
// and once every branch has ended fails with the first in that order — or,
// at the call with the route, gives it as a [Caught]. The futures awaited are
// the same either way, so the effects get the same keys as without a route.

import 'dart:async';

import 'call_limit.dart';
import 'failure.dart';
import 'flow.dart';
import 'graph.dart';

/// Runs [shape] with [input] in the session of [flow] this is called in, as
/// a part of [copies], the copies of calls with a limit it is in, the
/// outermost first; gives the output that went nowhere last — `null` when
/// none did — through [output], which checks its type.
///
/// Throws what a node, a route or [output] threw, once every branch has
/// ended: as it comes when no failure route catches it ([failures]
/// [Failures.thrown]), of the branches that failed the first in the graph's
/// order when one does. With [Failures.caught], gives that failure as a
/// [Caught] instead, while the session goes on.
Future<Object?> runGraph(
  GraphShape shape,
  Flow flow,
  Object? input, {
  List<CallCopy> copies = const [],
  Failures failures = Failures.thrown,
  Object? Function(Object? output) output = _same,
}) => _Run(shape, flow, copies, failures).run(input, output);

Object? _same(Object? output) => output;

/// A node a route leads to, with its input and, for a call with a limit,
/// the copy of it.
typedef _Called = (ShapeNode node, Object? input, CallCopy? copy);

/// Where a branch is in the graph's order: the index of its start, then of
/// each branch it was started as among those a route gave — the nodes of a
/// set in order, then the joins it leads.
typedef _Place = List<int>;

/// One run of a graph.
final class _Run {
  _Run(this._shape, this._flow, this._copies, this._failures);

  final GraphShape _shape;
  final Flow _flow;

  /// The copies of calls with a limit the run is a part of, the outermost
  /// first.
  final List<CallCopy> _copies;

  /// What a failure of the run comes to: whether a failure route catches
  /// it, round the call of the graph or at it.
  final Failures _failures;

  /// Whether a failure route catches the run's failure: its branches keep
  /// theirs in [_failed], and its effects' failures are final.
  bool get _kept => _failures != Failures.thrown;

  /// The failures of the branches of a run whose failure is [_kept], with
  /// the place of each branch.
  final _failed = <(_Place, Object, StackTrace)>[];

  /// The call sites of the run whose calls gave a limit, by the node or the
  /// join whose route calls, whether that route is a failure route, and the
  /// node called.
  final _sites = <(Object, bool, ShapeNode), CallSite>{};

  /// How many branches run now: neither ended nor waiting for the branches
  /// they started.
  int _running = 0;

  final _joins = Map<ShapeJoin, _JoinState>.identity();

  /// The output that went nowhere last.
  ({Object? value})? _result;

  Future<Object?> run(
    Object? input,
    Object? Function(Object? output) output,
  ) async {
    await Future.wait([
      for (final (i, start) in _shape.starts.indexed)
        _branch((start, input, null), [i]),
    ]);
    if (!_kept) return output(_result?.value);
    try {
      if (_firstFailed() case (_, final error, final stack)?) {
        Error.throwWithStackTrace(error, stack);
      }
      return output(_result?.value);
    } catch (error) {
      if (_failures != Failures.caught) rethrow;
      // A stop, or the end of the session by a failure of its store or a
      // codec, is no failure: it goes on as it is.
      checkGoesOn(_flow, _shape.name);
      return Caught(failureOf(error));
    }
  }

  /// Of the failures of the branches, the one of the branch first in the
  /// graph's order; `null` when none failed.
  (_Place, Object, StackTrace)? _firstFailed() {
    (_Place, Object, StackTrace)? first;
    for (final failed in _failed) {
      if (first == null || _before(failed.$1, first.$1)) first = failed;
    }
    return first;
  }

  /// Runs [first] and what follows it: in place while one node follows, in
  /// branches side by side when several do. [place] is where the branch is
  /// in the graph's order.
  Future<void> _branch(_Called first, _Place place) async {
    _running++;
    var waiting = false;
    try {
      var (node, value, copy) = first;
      while (true) {
        final Object? output;
        try {
          // Awaited right here, as without a limit: the branch goes on in the
          // context of the node's effect. A call with a failure route gives
          // its failure as a value, so the branch goes on from it there too.
          output = await _call(node, value, copy);
        } finally {
          copy?.end();
        }
        final failed = output is Caught;
        final List<(ShapeNode, Object?, int?)> targets;
        final leads = <_JoinState>[];
        if (output is Caught) {
          // A call that failed gave no output: no join takes one from it,
          // and it is no end of the graph.
          final input = value;
          targets = _next(
            'the failure route of ${node.name}',
            (failure) => node.failed!(input, failure! as CallFailure),
            output.failure,
          );
        } else {
          targets = _next('the route of ${node.name}', node.route, output);
          for (final join in node.joins) {
            final state = _joins[join] ??= _JoinState(this, join);
            if (identical(join.sources.first, node)) {
              leads.add(state);
            } else {
              state.deposit(node, output);
            }
          }
        }
        final next = _called(node, targets, failed: failed);
        // A node of a join without arrows of its own gave its output to the
        // join: it is no end of the graph.
        if (!failed &&
            next.isEmpty &&
            (node.route != null || node.joins.isEmpty)) {
          _result = (value: output);
        }
        if (leads.isEmpty && next.length == 1) {
          (node, value, copy) = next.single;
          continue;
        }
        if (leads.isEmpty && next.isEmpty) return;
        final started = [
          for (final (i, called) in next.indexed)
            _branch(called, [...place, i]),
          for (final (i, state) in leads.indexed)
            _lead(state, output, [...place, next.length + i]),
        ];
        waiting = true;
        _ran();
        await Future.wait(started);
        return;
      }
    } catch (error, stack) {
      if (!_kept) rethrow;
      _failed.add((place, error, stack));
    } finally {
      if (!waiting) _ran();
    }
  }

  /// Runs the node of [at] on [value], as [copy] when it is a call with a
  /// limit: an effect for a node, the graph's own nodes for a graph. When
  /// [at] has a failure route, the call gives its failure as a [Caught].
  Future<Object?> _call(ShapeNode at, Object? value, CallCopy? copy) {
    final copies = copy == null ? _copies : [..._copies, copy];
    final failures = at.failed != null
        ? Failures.caught
        : _kept
        ? Failures.kept
        : Failures.thrown;
    return switch (at.node) {
      final Node<Object?, Object?> node => nodeEffect(
        _flow,
        _shape.name,
        node,
        value,
        copies: copies,
        failures: failures,
      ),
      final Graph<Object?, Object?> graph => graph.runWith(
        _flow,
        value,
        copies: copies,
        failures: failures,
      ),
    };
  }

  /// [next], the nodes the route of [from] — a node or a join, its failure
  /// route when [failed] — leads to, each with its input and, when it gives
  /// a limit, a copy of its call site, made now: in the order the route
  /// gives them, once it has given them all.
  List<_Called> _called(
    Object from,
    List<(ShapeNode, Object?, int?)> next, {
    bool failed = false,
  }) => [
    for (final (node, input, limit) in next)
      (
        node,
        input,
        limit == null
            ? null
            : (_sites[(from, failed, node)] ??= CallSite()).copy(limit),
      ),
  ];

  /// The nodes that follow [output], each with its input and the limit of
  /// its call, as [route], named [name] in errors, gives them: none when
  /// there is no route, or it gives `null` or an empty set.
  ///
  /// Throws a [StateError] naming the graph when the route gives anything
  /// else than a [Next], a set of them or `null`, or a node whose name another
  /// node of the graph has; and what the route throws.
  List<(ShapeNode, Object?, int?)> _next(
    String name,
    Object? Function(Object? output)? route,
    Object? output,
  ) {
    if (route == null) return const [];
    final given = route(output);
    return switch (given) {
      null => const [],
      final Next next => [
        (_shape.nodeFor(next.target), next.input, next.limit),
      ],
      final Set<Object?> set when set.every((next) => next is Next) => [
        for (final next in set.whereType<Next>())
          (_shape.nodeFor(next.target), next.input, next.limit),
      ],
      _ => throw StateError(
        'graph "${_shape.name}": $name gave $given: a route gives a Next, a '
        'set of them or null',
      ),
    };
  }

  /// Goes on from [state] after its first node gave [output]: once every other
  /// node of the join has given an output, its route leads on from the record
  /// of them; ends when the join can no longer fill up. [place] is where it
  /// is in the graph's order.
  Future<void> _lead(_JoinState state, Object? output, _Place place) async {
    final outputs = await state.arrive(output);
    if (outputs == null) return;
    final List<Future<void>> started;
    try {
      final List<(ShapeNode, Object?, int?)> next;
      try {
        next = _next(
          'the route of ${state.join.name}',
          state.join.route,
          outputs,
        );
      } on TypeError catch (error) {
        // A join's route declares the type of the record it takes, which the
        // compiler cannot check against its nodes: the dynamic call in
        // `Part.next` does, here.
        throw StateError(
          'graph "${_shape.name}": the route of ${state.join.name} threw a '
          'TypeError on the record ${outputs.runtimeType} of their outputs: it '
          'takes another record, or has a type error of its own: $error',
        );
      }
      if (next.isEmpty) _result = (value: outputs);
      started = [
        for (final (i, called) in _called(state.join, next).indexed)
          _branch(called, [...place, i]),
      ];
    } catch (error, stack) {
      if (!_kept) rethrow;
      _failed.add((place, error, stack));
      return;
    } finally {
      // Counted as running from when it filled up, so that no other branch
      // ending in between gives up the joins this one may fill.
      _ran();
    }
    await Future.wait(started);
  }

  /// A branch stopped running. When none runs, no join can fill up any more:
  /// the branches waiting at joins end.
  void _ran() {
    _running--;
    if (_running == 0) {
      for (final state in _joins.values) {
        state.abandon();
      }
    }
  }
}

/// What a join of a run has been given so far.
final class _JoinState {
  _JoinState(this._run, this.join)
    : _outputs = [for (final _ in join.sources) <Object?>[]];

  final _Run _run;
  final ShapeJoin join;

  /// The outputs given and not yet taken, for each node but the first, by
  /// its place in the join.
  final List<List<Object?>> _outputs;

  /// The outputs of the first node that wait for the others', with what each
  /// is given: the record, or `null` when the join cannot fill up.
  final _waiting = <(Object?, Completer<Record?>)>[];

  /// The record of the first node's [output] and the next output of each
  /// other node, once all are there; `null` when they no longer can be.
  Future<Record?> arrive(Object? output) {
    final filled = Completer<Record?>();
    _waiting.add((output, filled));
    _fire();
    return filled.future;
  }

  /// Takes [output] of [node], a node of the join but its first.
  void deposit(ShapeNode node, Object? output) {
    _outputs[join.sources.indexOf(node)].add(output);
    _fire();
  }

  /// Gives the records that can be made.
  void _fire() {
    while (_waiting.isNotEmpty &&
        _outputs.skip(1).every((outputs) => outputs.isNotEmpty)) {
      final (first, filled) = _waiting.removeAt(0);
      final values = [
        first,
        for (final outputs in _outputs.skip(1)) outputs.removeAt(0),
      ];
      _run._running++;
      filled.complete(_record(values));
    }
  }

  /// The join cannot fill up any more: every first node's output that waits
  /// is given `null`.
  void abandon() {
    for (final (_, filled) in _waiting) {
      filled.complete(null);
    }
    _waiting.clear();
  }
}

/// Whether the branch at [a] comes before the one at [b] in the graph's
/// order: at the first index where they differ, or as the one [b] was
/// started from.
bool _before(_Place a, _Place b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return a[i] < b[i];
  }
  return a.length < b.length;
}

/// The record of [values], 2 to 6 of them.
Record _record(List<Object?> values) => switch (values) {
  [final a, final b] => (a, b),
  [final a, final b, final c] => (a, b, c),
  [final a, final b, final c, final d] => (a, b, c, d),
  [final a, final b, final c, final d, final e] => (a, b, c, d, e),
  [final a, final b, final c, final d, final e, final f] => (a, b, c, d, e, f),
  _ => throw StateError('a join takes 2 to 6 nodes, not ${values.length}'),
};
