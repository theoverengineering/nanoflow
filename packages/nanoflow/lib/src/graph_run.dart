// Runs a graph's shape in the session it is called in (graph design §5–§8).
//
// The graph is run by code that awaits its nodes as a hand-written workflow
// function would: a branch awaits a node — a node that is a function of one
// parameter is an effect —, goes on in place while one node follows, and
// starts the nodes that follow side by side with `Future.wait` when several
// do. So the effects of a graph get keys and `after`s as those of a function
// do: the same on every run, whatever the timing (spec §4.3).
//
// A join goes on from the branch of its first node, once every other node of
// it has given an output: its targets so run in the context of the first
// node's effect, whichever node gave its output last. A join that never fills
// up would hold its branch for ever; once no branch runs, nothing can fill it
// any more, and the branches waiting at joins end.

import 'dart:async';

import 'flow.dart';
import 'graph.dart';

/// Runs [shape] with [input] in the session of [flow] this is called in;
/// gives the output that went nowhere last, `null` when none did.
///
/// Throws what a node threw, once every branch has ended.
Future<Object?> runGraph(GraphShape shape, Flow flow, Object? input) =>
    _Run(shape, flow).run(input);

/// One run of a graph.
final class _Run {
  _Run(this._shape, this._flow);

  final GraphShape _shape;
  final Flow _flow;

  /// How many branches run now: neither ended nor waiting for the branches
  /// they started.
  int _running = 0;

  final _joins = Map<ShapeJoin, _JoinState>.identity();

  /// The output that went nowhere last.
  ({Object? value})? _result;

  Future<Object?> run(Object? input) async {
    await Future.wait([
      for (final start in _shape.starts) _branch(start, input),
    ]);
    return _result?.value;
  }

  /// Runs [first] on [input] and what follows it: in place while one node
  /// follows, in branches side by side when several do.
  Future<void> _branch(ShapeNode first, Object? input) async {
    _running++;
    var waiting = false;
    try {
      var node = first;
      var value = input;
      while (true) {
        final output = await _call(node, value);
        final next = _routes(node, output);
        final leads = <_JoinState>[];
        for (final join in node.joins) {
          final state = _joins[join] ??= _JoinState(this, join);
          if (identical(join.sources.first, node)) {
            leads.add(state);
          } else {
            state.deposit(node, output);
          }
        }
        if (next.isEmpty && node.joins.isEmpty) _result = (value: output);
        if (leads.isEmpty && next.length == 1) {
          (node, value) = next.single;
          continue;
        }
        if (leads.isEmpty && next.isEmpty) return;
        final started = [
          for (final (target, payload) in next) _branch(target, payload),
          for (final state in leads) _lead(state, output),
        ];
        waiting = true;
        _ran();
        await Future.wait(started);
        return;
      }
    } finally {
      if (!waiting) _ran();
    }
  }

  /// Runs [node] on [value]: an effect for a function of one parameter, a
  /// call for a workflow function or a graph.
  Future<Object?> _call(ShapeNode node, Object? value) => switch (node.kind) {
    NodeKind.function => nodeEffect(_flow, _shape, node, value),
    NodeKind.workflow || NodeKind.graph => switch ((node.node as dynamic)(
      _flow,
      value,
    )) {
      final Future<Object?> future => future,
      final other => Future.value(other),
    },
  };

  /// Where [output], given by [node], goes, and what each target gets.
  List<(ShapeNode, Object?)> _routes(ShapeNode node, Object? output) {
    switch (node.routes) {
      case null:
        return const [];
      case AllRoutes(:final targets):
        return [for (final target in targets) (target, output)];
      case CaseRoutes(:final cases, :final otherwise):
        final (subject, payload) = switch (output) {
          (final key, final payload) => (key, payload),
          Exit(:final value) => (output, value),
          _ => (output, output),
        };
        for (final (:key, :targets) in cases) {
          if (key is Type ? subject.runtimeType == key : subject == key) {
            return [for (final target in targets) (target, payload)];
          }
        }
        return [for (final target in otherwise) (target, output)];
    }
  }

  /// Goes on from [state] after its first node gave [output]: once every other
  /// node of the join has given an output, runs its targets on the record of
  /// them; ends when the join can no longer fill up.
  Future<void> _lead(_JoinState state, Object? output) async {
    final outputs = await state.arrive(output);
    if (outputs == null) return;
    final started = [
      for (final target in state.join.targets) _branch(target, outputs),
    ];
    // Counted as running from when it filled up, so that no other branch
    // ending in between gives up the joins this one may fill.
    _ran();
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

/// The record of [values], 2 to 6 of them.
Record _record(List<Object?> values) => switch (values) {
  [final a, final b] => (a, b),
  [final a, final b, final c] => (a, b, c),
  [final a, final b, final c, final d] => (a, b, c, d),
  [final a, final b, final c, final d, final e] => (a, b, c, d, e),
  [final a, final b, final c, final d, final e, final f] => (a, b, c, d, e, f),
  _ => throw StateError('a join takes 2 to 6 nodes, not ${values.length}'),
};
