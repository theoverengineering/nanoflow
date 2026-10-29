// What passes.dart marks, checked against runs of random programs (effects
// design §5). A program is a workflow and the functions it calls, made of
// effects, `if`, `while`, calls, closures called in place, `Future.wait` of
// effects and calls, `return`, and effects in a closure passed on, which
// describe does not draw. Each function is drawn as describe draws it (spec
// §7.1) and run as the library runs it, its journal keyed as the library keys
// it (spec §4.3, packages/nanoflow/lib/src/context.dart): an effect comes
// after the last effect whose result its context took; a call, a closure and
// each branch of a wait begin with their caller's, and the caller goes on
// after them with its own — unless what it awaited hands it an effect's very
// result, as `return f.effect(…)` does.
//
// On the body of every function, after the session finished and at moments
// while it ran, failed or was cut off: every fork passed and every edge taken
// is on the way the code went, and no exit the code took is darker — but in
// a session that falls in a limit of the journal, which the rules cannot get
// right from it (passes.dart «Limits», design §5.3 «Пределы»). The run knows
// what the journal does not — which effects each effect waited for, which
// call of a function each ran in —, and leaves out a session that falls in
// one of three: effects side by side read as joined; the ends of an earlier
// call of a function read as joined before an effect of a later one; effects
// side by side that end in the millisecond they start, passing each other.
// The classes are drawn wide: in many sessions left out the marks are right
// all the same. Outside them, no run of the seeds tried so far has marked a
// way the code did not go or darkened one it took; that is what the test
// asserts, and the classes are limits it found, not a proof that no other
// is left. How often each comes up is bounded. A quarter of the effects end
// in the millisecond they start, as fast effects of the library do. How many
// times a fork was passed is not checked: the journal does not always tell
// (design §5.2).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/effect_places.dart';
import 'package:nanoflow_ui/state/passes.dart';
import 'package:nanoflow_ui/state/session_feed.dart';

import 'support.dart';

void main() {
  test('random programs: the forks marked passed and the edges taken are '
      'on the way the code went, and no exit it went along is darker, in '
      'every session the run does not find in a limit of the journal', () {
    final (:sessions, :left, :wrong) = _runs(Random(20261005), 4000);
    expect(wrong, isEmpty);
    expect(sessions, greaterThan(14000));
    // Over seeds 1–40 at this size, and 41–200 at 25,000 programs, side by
    // side came up in 3.5–4.6% of the sessions, the ends of an earlier call
    // in 1.0–1.8%, effects passing each other in 1.2–2.0%.
    expect(left[_Limit.sideBySide]!, lessThan(sessions * 6 ~/ 100));
    expect(left[_Limit.earlierCall]!, lessThan(sessions * 3 ~/ 100));
    expect(left[_Limit.tied]!, lessThan(sessions * 4 ~/ 100));
  });
}

/// Runs [programs] random programs made with [random], each finished and
/// cut off once running, once failed, once interrupted: how many sessions,
/// how many of them were left out for each limit of the journal, and what
/// was wrong in the others, by session.
({int sessions, Map<_Limit, int> left, List<String> wrong}) _runs(
  Random random,
  int programs,
) {
  var sessions = 0;
  final left = {for (final limit in _Limit.values) limit: 0};
  final wrong = <String>[];
  for (var n = 0; n < programs; n++) {
    final program = _Generator(random).program();
    final run = _Run(program, random)..start();
    if (run.records.isEmpty) continue;
    for (final (:status, :cut) in <({String status, int? cut})>[
      (status: 'finished', cut: null),
      for (final status in ['running', 'failed', 'interrupted'])
        (status: status, cut: random.nextInt(run.last + 2)),
    ]) {
      sessions++;
      final limits = _limitsOf(program, run, cut);
      for (final limit in limits) {
        left[limit] = left[limit]! + 1;
      }
      if (limits.isNotEmpty) continue;
      final errors = _check(program, run, status: status, cut: cut);
      if (errors.isNotEmpty) {
        wrong.add(
          '$status${cut == null ? '' : ' before tick $cut'}: '
          '${errors.join('; ')}\n'
          '${program.source}\njournal: ${run.journal(cut)}',
        );
      }
    }
  }
  return (sessions: sessions, left: left, wrong: wrong);
}

/// A limit of the journal (passes.dart, «Limits»; design §5.3 «Пределы»):
/// where a session falls in one, the rules may mark a way the code did not
/// go, and the session is left out of the check.
enum _Limit {
  /// Effects side by side that end before another starts read as joined
  /// before it.
  sideBySide,

  /// The ends of an earlier call of a function read as joined before an
  /// effect of a later call, on the body of the function.
  earlierCall,

  /// Effects side by side that end in the millisecond they start, in one call
  /// node or leading to each other round a loop, read as joined before each
  /// other, and so as passed: the effect after them finds all its ends
  /// passed.
  tied,
}

/// The limits the journal of [run] of [program] before the tick [cut] falls
/// in, by what the run knows and the journal does not: there is an effect E
/// on the graph, and an effect O on the graph, below what E follows, that no
/// effect on the graph follows and that had finished by E's first start in
/// the journal's milliseconds — an end the rules may join before E — and
///
/// - [_Limit.sideBySide]: E's code did not wait for O, and O leads to E on a
///   body;
/// - [_Limit.earlierCall]: O and E are in different calls of a function,
///   and O leads to E on its body, or is in one call node of it with E;
/// - [_Limit.tied]: O and E started and ended in one millisecond, beside
///   each other, and each leads to the other on a body or is in one call
///   node with it — the rules read each as joined before the other,
///   and so as passed —, and both are such ends before a later effect.
Set<_Limit> _limitsOf(_Program program, _Run run, int? cut) {
  final recorded = [
    for (final r in run.records)
      if (cut == null || r.start < cut) r,
  ];
  final byKey = {for (final r in recorded) r.key: r};
  bool onGraph(_Record r) => r.place == _placeOf(r.name);
  _Record? up(_Record r) {
    for (var key = r.after; key != null; key = byKey[key]?.after) {
      final before = byKey[key];
      if (before == null) return null;
      if (onGraph(before)) return before;
    }
    return null;
  }

  final followed = {
    for (final r in recorded)
      if (onGraph(r)) up(r)?.key,
  };
  bool below(_Record o, _Record? parent) {
    if (parent == null) return true;
    for (var a = up(o); a != null; a = up(a)) {
      if (a.key == parent.key) return true;
    }
    return false;
  }

  final limits = <_Limit>{};
  // Ends that started and ended in the millisecond an effect beside them
  // started, with that effect.
  final beside = <(_Record, _Record)>[];
  // The ends the rules may join before each effect.
  final ends = <_Record, List<_Record>>{};
  for (final e in recorded) {
    if (!onGraph(e)) continue;
    final parent = up(e);
    for (final o in recorded) {
      if (identical(o, e) ||
          !onGraph(o) ||
          followed.contains(o.key) ||
          (cut != null && o.end >= cut) ||
          o.end ~/ 2 > e.start ~/ 2 ||
          !below(o, parent)) {
        continue;
      }
      (ends[e] ??= []).add(o);
      if (e.past & 1 << o.order == 0 &&
          !limits.contains(_Limit.sideBySide) &&
          program.functions.any(
            (function) => _leads(program, function.body, o, e),
          )) {
        limits.add(_Limit.sideBySide);
      }
      if (e.past & 1 << o.order == 0 && o.start ~/ 2 == e.start ~/ 2) {
        beside.add((o, e));
      }
      for (final MapEntry(key: function, value: call) in o.calls.entries) {
        if (limits.contains(_Limit.earlierCall)) break;
        final other = e.calls[function];
        if (other == null || other == call) continue;
        final body = program.functions[function].body;
        if (_leads(program, body, o, e, inside: true)) {
          limits.add(_Limit.earlierCall);
        }
      }
    }
  }
  // An end beside the effect it reads as joined before is passed by it, for
  // a later effect it would be an end before.
  bool leads(_Record o, _Record e) => program.functions.any(
    (function) => _leads(program, function.body, o, e, inside: true),
  );
  // Two that each read as joined before the other pass each other: a later
  // effect they would both be ends before finds neither.
  for (final (o, other) in beside) {
    if (!beside.contains((other, o)) || !leads(o, other) || !leads(other, o)) {
      continue;
    }
    for (final MapEntry(key: e, value: before) in ends.entries) {
      if (o.start ~/ 2 < e.start ~/ 2 &&
          before.contains(o) &&
          before.contains(other)) {
        limits.add(_Limit.tied);
        return limits;
      }
    }
  }
  return limits;
}

/// The nodes of [body] the effect [record] is on or in.
List<String> _nodesOn(_Program program, GraphBody body, _Record record) {
  final effect = Effect(
    id: record.key,
    sessionId: 'a1b2-session',
    name: record.name,
    key: record.key,
    after: record.after,
    place: record.place,
    outputId: null,
    log: logFileName,
  );
  return [
    for (final node in body.nodes)
      if (node is! ConditionNode && program.places.isIn(effect, node)) node.id,
  ];
}

/// Whether [from] and [to] are in one call node of [body].
bool _inOne(_Program program, GraphBody body, _Record from, _Record to) {
  final targets = _nodesOn(program, body, to).toSet();
  final sources = _nodesOn(program, body, from);
  return body.nodes.any(
    (node) =>
        node is! EffectNode &&
        targets.contains(node.id) &&
        sources.contains(node.id),
  );
}

/// Whether a way leads on [body] from the nodes [from] is on or in to those
/// [to] is, through forks and calls; or, when [inside], they share a call
/// node.
bool _leads(
  _Program program,
  GraphBody body,
  _Record from,
  _Record to, {
  bool inside = false,
}) {
  if (inside && _inOne(program, body, from, to)) return true;
  final targets = _nodesOn(program, body, to).toSet();
  final ahead = _nodesOn(program, body, from);
  if (targets.isEmpty || ahead.isEmpty) return false;
  final passable = {
    for (final node in body.nodes)
      if (node is! EffectNode) node.id,
  };
  final reached = {...ahead};
  while (ahead.isNotEmpty) {
    final node = ahead.removeLast();
    for (final edge in body.edges) {
      if (edge.from != node || edge.to == null) continue;
      if (targets.contains(edge.to)) return true;
      if (passable.contains(edge.to) && reached.add(edge.to!)) {
        ahead.add(edge.to!);
      }
    }
  }
  return false;
}

/// What is wrong with the passes of [run] of [program] on each body, the
/// session [status] — cut off before the tick [cut] unless finished.
List<String> _check(
  _Program program,
  _Run run, {
  required String status,
  required int? cut,
}) {
  final session = run.session(status: status, cut: cut);
  final wrong = <String>[];
  for (final (i, function) in program.functions.indexed) {
    final body = function.body;
    final passes = Passes.of(
      body,
      places: program.places,
      session: session,
      effects: session.state.effects,
    );
    final route = {
      for (final MapEntry(key: edge, value: time) in run.routes[i].entries)
        if (cut == null || time < cut) edge,
    };
    final reached = {
      for (final edge in route) ...[body.edges[edge].from, body.edges[edge].to],
    };
    String text(int edge) =>
        '${body.edges[edge].from ?? ''}>${body.edges[edge].to ?? ''}';
    for (final node in body.nodes) {
      if (passes.of(node.id) > 0 && !reached.contains(node.id)) {
        wrong.add('${function.name}: ${node.id} passed, never reached');
      }
    }
    for (var edge = 0; edge < body.edges.length; edge++) {
      if (passes.taken(edge) && !route.contains(edge)) {
        wrong.add('${function.name}: ${text(edge)} taken, never gone along');
      }
      if (passes.untaken(edge) && route.contains(edge)) {
        wrong.add('${function.name}: ${text(edge)} darker, gone along');
      }
    }
  }
  return wrong;
}

// ---- programs ----------------------------------------------------------------

/// A statement of a random program.
sealed class _Statement {
  /// The statement as Dart source, indented by [indent].
  String source(String indent);
}

/// `await f.effect('name', …)`; also an effect a `Future.wait` waits for, and
/// one `return` hands on.
final class _Effect extends _Statement {
  _Effect(this.name);

  final String name;

  /// Its node; `null` until drawn.
  _Vertex? vertex;

  @override
  String source(String indent) => "${indent}await f.effect('$name');";
}

/// `await retry(() => f.effect('name', …))`: an effect in a closure passed
/// on, which describe does not draw. When [handsOn], `retry` hands the
/// effect's own future on (`=> body()`), so the code that awaits it takes the
/// effect's result.
final class _Hidden extends _Statement {
  _Hidden(this.name, {required this.handsOn});

  final String name;
  final bool handsOn;

  @override
  String source(String indent) =>
      "${indent}await ${handsOn ? 'handOn' : 'retry'}(() => "
      "f.effect('$name'));";
}

final class _If extends _Statement {
  _If(this.label, this.then, this.otherwise);

  final String label;
  final List<_Statement> then;
  final List<_Statement> otherwise;
  _Vertex? fork;

  @override
  String source(String indent) => [
    '${indent}if ($label) {',
    for (final s in then) s.source('$indent  '),
    if (otherwise.isNotEmpty) ...[
      '$indent} else {',
      for (final s in otherwise) s.source('$indent  '),
    ],
    '$indent}',
  ].join('\n');
}

/// `while (label) body`, going round at most [_rounds] times.
final class _While extends _Statement {
  _While(this.label, this.body);

  final String label;
  final List<_Statement> body;
  _Vertex? fork;

  @override
  String source(String indent) => [
    '${indent}while ($label) {',
    for (final s in body) s.source('$indent  '),
    '$indent}',
  ].join('\n');
}

const _rounds = 3;

/// `await f<callee>(f);`, or the call in a branch of a wait.
final class _Call extends _Statement {
  _Call(this.callee);

  final int callee;
  _Vertex? vertex;

  @override
  String source(String indent) => '${indent}await f$callee(f);';
}

/// `await (() async { body })();`, drawn in place.
final class _Closure extends _Statement {
  _Closure(this.body);

  final List<_Statement> body;

  @override
  String source(String indent) => [
    '${indent}await (() async {',
    for (final s in body) s.source('$indent  '),
    '$indent})();',
  ].join('\n');
}

/// `await Future.wait([…])` of effects and calls.
final class _Wait extends _Statement {
  _Wait(this.branches);

  /// Each an [_Effect] or a [_Call].
  final List<_Statement> branches;

  @override
  String source(String indent) =>
      '${indent}await Future.wait([${[for (final b in branches) switch (b) {
          _Effect(:final name) => "f.effect('$name')",
          _Call(:final callee) => 'f$callee(f)',
          _ => '?',
        }].join(', ')}]);';
}

/// `return;`, or `return f.effect('name', …);` when there is a [tail].
final class _Return extends _Statement {
  _Return(this.tail);

  final _Effect? tail;

  @override
  String source(String indent) => switch (tail) {
    final tail? => "${indent}return f.effect('${tail.name}');",
    null => '${indent}return;',
  };
}

/// Whether [statements] hold an effect or a call describe draws, or a
/// `return` out of them — one in a closure called in place leaves only the
/// closure: unless [returns], it does not count.
bool _drawn(List<_Statement> statements, {bool returns = true}) =>
    statements.any(
      (s) => switch (s) {
        _Effect() || _Call() || _Wait() => true,
        _Return(:final tail) => tail != null || returns,
        _Hidden() => false,
        _If(:final then, :final otherwise) =>
          _drawn(then, returns: returns) || _drawn(otherwise, returns: returns),
        _While(:final body) => _drawn(body, returns: returns),
        _Closure(:final body) => _drawn(body, returns: false),
      },
    );

/// A workflow, `f0`, and the functions it calls, `f1`, `f2`…: a function
/// calls only those after it.
final class _Program {
  _Program(this.bodies) {
    functions = [
      for (final (i, statements) in bodies.indexed)
        GraphFunction(
          id: 'lib/flow.dart#f$i',
          name: 'f$i',
          place: null,
          body: (_drawings[i] = _Drawing()).draw(statements),
        ),
    ];
    places = EffectPlaces.of(functions.first, {
      for (final function in functions) function.id: function,
    });
  }

  final List<List<_Statement>> bodies;
  late final List<GraphFunction> functions;
  late final EffectPlaces places;
  final Map<int, _Drawing> _drawings = {};

  String get source => [
    for (final (i, statements) in bodies.indexed) ...[
      'Future<void> f$i(Flow f) async {',
      for (final s in statements) s.source('  '),
      '}',
    ],
    for (final (i, function) in functions.indexed)
      'f$i: ${[for (final e in function.body.edges) '${e.from ?? ''}>${e.to ?? ''}'].join(' ')}',
  ].join('\n');
}

/// The place of the effect [name] when drawn.
String _placeOf(String name) => 'lib/flow.dart:$name';

/// Makes random programs: each function but the workflow is called by one
/// function before it alone, so that on the body of a function the effects
/// in its calls came through it (an effect is on a call node by its place,
/// whoever called the function).
final class _Generator {
  _Generator(this.random);

  final Random random;
  late final int _count = 1 + random.nextInt(3);

  /// By function, the functions it calls.
  late final List<List<int>> _callees = () {
    final callees = [for (var i = 0; i < _count; i++) <int>[]];
    for (var i = 1; i < _count; i++) {
      callees[random.nextInt(i)].add(i);
    }
    return callees;
  }();

  var _names = 0;
  var _labels = 0;

  _Program program() =>
      _Program([for (var i = 0; i < _count; i++) _function(i)]);

  List<_Statement> _function(int i) {
    final body = _block(i, 0, least: 1);
    if (!_drawn(body)) body.insert(0, _effect());
    return body;
  }

  _Effect _effect() => _Effect('e${_names++}');

  List<_Statement> _block(int function, int depth, {int least = 0}) {
    final block = [
      for (var n = least + random.nextInt(depth == 0 ? 3 : 2); n > 0; n--)
        _statement(function, depth),
    ];
    if (random.nextInt(6) == 0) {
      block.add(_Return(random.nextBool() ? _effect() : null));
    }
    return block;
  }

  _Statement _statement(int function, int depth) {
    final callees = _callees[function];
    _Call call() => _Call(callees[random.nextInt(callees.length)]);
    final r = random.nextInt(100);
    if (depth >= 2 || r < 28) return _effect();
    if (r < 48) {
      return _If(
        'c${_labels++}',
        _block(function, depth + 1, least: 1),
        random.nextBool() ? const [] : _block(function, depth + 1),
      );
    }
    if (r < 58) {
      return _While('w${_labels++}', _block(function, depth + 1, least: 1));
    }
    if (r < 72 && callees.isNotEmpty) return call();
    if (r < 84) {
      return _Wait([
        for (var n = 2 + random.nextInt(2); n > 0; n--)
          callees.isNotEmpty && random.nextInt(3) == 0 ? call() : _effect(),
      ]);
    }
    if (r < 90) return _Closure(_block(function, depth + 1, least: 1));
    if (r < 96) return _Hidden('h${_names++}', handsOn: random.nextBool());
    return _effect();
  }
}

// ---- drawing -------------------------------------------------------------------

/// A point of a body as describe makes it before it emits the graph.
final class _Vertex {
  _Vertex(this.kind, {this.name, this.callee});

  /// `effect`, `fork`, `call`, `join`, `entry` or `exit`.
  final String kind;
  final String? name;
  final int? callee;

  /// Its node's id once emitted; `null` for one not drawn.
  String? id;
}

typedef _Out = (_Vertex, String?);

/// A body drawn as describe draws it (packages/nanoflow_describe/lib/src/
/// extract.dart): vertices and the edges between them, a fork whose outcomes
/// all lead to the same points hidden, edges going through hidden points.
final class _Drawing {
  final entry = _Vertex('entry');
  final exit = _Vertex('exit');
  final _vertices = <_Vertex>[];
  final _edges = <_Vertex, List<(String?, _Vertex)>>{};

  /// The forks and joins not drawn.
  final hidden = <_Vertex>{};

  /// The index of each edge in the body by its ends and label.
  final _index = <(String?, String?, String?), int>{};

  GraphBody draw(List<_Statement> statements) {
    _connect(_block(statements, [(entry, null)], null), exit);
    return _emit();
  }

  /// The index of the edge from [from] by [label] to [to]: the code went
  /// along it.
  int edge(_Vertex from, String? label, _Vertex to) {
    final index = _index[(from.id, to.id, label)];
    if (index == null) {
      throw StateError('no edge ${from.id} -$label-> ${to.id}');
    }
    return index;
  }

  _Vertex _add(_Vertex v) {
    _vertices.add(v);
    return v;
  }

  void _connect(List<_Out> from, _Vertex to) {
    for (final (v, label) in from) {
      (_edges[v] ??= []).add((label, to));
    }
  }

  List<_Out> _block(
    List<_Statement> statements,
    List<_Out> into,
    List<_Out>? returns,
  ) {
    var current = into;
    for (final s in statements) {
      current = _statement(s, current, returns);
    }
    return current;
  }

  List<_Out> _statement(_Statement s, List<_Out> into, List<_Out>? returns) {
    if (into.isEmpty || !_drawn([s])) return into;
    switch (s) {
      case _Effect():
        final v = s.vertex = _add(_Vertex('effect', name: s.name));
        _connect(into, v);
        return [(v, null)];
      case _Call():
        final v = s.vertex = _add(_Vertex('call', callee: s.callee));
        _connect(into, v);
        return [(v, null)];
      case _Hidden():
        return into;
      case _If():
        final fork = s.fork = _add(_Vertex('fork', name: s.label));
        _connect(into, fork);
        return [
          ..._block(s.then, [(fork, 'true')], returns),
          ..._block(s.otherwise, [(fork, 'false')], returns),
        ];
      case _While():
        final head = _add(_Vertex('join'));
        _connect(into, head);
        final fork = s.fork = _add(_Vertex('fork', name: s.label));
        _connect([(head, null)], fork);
        _connect(_block(s.body, [(fork, 'true')], returns), head);
        return [(fork, 'false')];
      case _Closure():
        final closureReturns = <_Out>[];
        final exits = _block(s.body, into, closureReturns);
        return [...exits, ...closureReturns];
      case _Wait():
        return [
          for (final branch in s.branches) ..._statement(branch, into, returns),
        ];
      case _Return():
        final out = switch (s.tail) {
          final tail? => _statement(tail, into, returns),
          null => into,
        };
        if (returns != null) {
          returns.addAll(out);
        } else {
          _connect(out, exit);
        }
        return const [];
    }
  }

  GraphBody _emit() {
    hidden.addAll(_vertices.where((v) => v.kind == 'join'));
    for (var changed = true; changed;) {
      changed = false;
      for (final fork in _vertices.where((v) => v.kind == 'fork')) {
        if (hidden.contains(fork)) continue;
        final outcomes = <String?, Set<_Vertex>>{'true': {}, 'false': {}};
        for (final (label, to)
            in _edges[fork] ?? const <(String?, _Vertex)>[]) {
          (outcomes[label] ??= {}).addAll(_resolve({to}));
        }
        final sets = outcomes.values.toList();
        if (sets.every(
          (s) => s.length == sets.first.length && s.containsAll(sets.first),
        )) {
          hidden.add(fork);
          changed = true;
        }
      }
    }
    var count = 0;
    final nodes = <GraphNode>[];
    for (final v in _vertices) {
      if (hidden.contains(v)) continue;
      final id = v.id = '${++count}';
      nodes.add(switch (v.kind) {
        'effect' => EffectNode(id: id, place: _placeOf(v.name!), name: v.name!),
        'fork' => ConditionNode(id: id, place: null, label: v.name!),
        _ => CallNode(
          id: id,
          place: null,
          functions: ['lib/flow.dart#f${v.callee}'],
        ),
      });
    }
    final edges = <GraphEdge>[];
    void edgesOf(_Vertex from) {
      for (final (label, to) in _edges[from] ?? const <(String?, _Vertex)>[]) {
        for (final target in _resolve({to})) {
          final key = (from.id, target.id, label);
          if (_index.containsKey(key)) continue;
          _index[key] = edges.length;
          edges.add(GraphEdge(from: from.id, to: target.id, label: label));
        }
      }
    }

    edgesOf(entry);
    for (final v in _vertices) {
      if (!hidden.contains(v)) edgesOf(v);
    }
    return GraphBody(nodes: nodes, edges: edges);
  }

  /// The drawn points [vs] lead to, or the exit, through hidden ones.
  Set<_Vertex> _resolve(Set<_Vertex> vs, [Set<_Vertex>? seen]) {
    seen ??= {};
    final result = <_Vertex>{};
    for (final v in vs) {
      if (!hidden.contains(v)) {
        result.add(v);
      } else if (seen.add(v)) {
        result.addAll(
          _resolve({
            for (final (_, to) in _edges[v] ?? const <(String?, _Vertex)>[]) to,
          }, seen),
        );
      }
    }
    return result;
  }
}

// ---- running -----------------------------------------------------------------

/// An effect the run called: the [order]th; the effects done before it
/// started on the way the code took to it, a bit set over their orders —
/// those of the code it awaited, not those beside it; and by each function
/// it was called in, which call of it.
typedef _Record = ({
  int order,
  String name,
  String key,
  String? after,
  String? place,
  int start,
  int end,
  int past,
  Map<int, int> calls,
});

/// The context code runs in, as far as `after` goes: the key of the effect
/// whose result it took last.
final class _Context {
  _Context(this.after);

  String? after;
}

/// Where the code of one call of a function, or of one branch, is on its
/// body: the drawn points it left last, each by its outcome.
typedef _At = List<_Out>;

/// Where the code is ([_At]) and when, and the effects done on its way
/// there ([_Record.past]).
typedef _Here = ({_At at, int time, int past});

/// What running statements came to: where the code is, and whether it
/// returned — handing on the key of the effect `return` gave, if one did.
typedef _Done = ({_Here here, bool returned, String? handed});

/// A run of a program: its effects with their keys and times, and the edges
/// of each body the code went along, each with when it first did.
///
/// Times are ticks, two to a millisecond of the journal. Code runs in turns:
/// in one turn, at an even tick, the code goes along its edges and calls
/// effects, which start a tick later and last one to three milliseconds —
/// or, one in four, end in the millisecond they started, as a fast effect of
/// the library does; the turn after an `await` comes when what it awaited is
/// done, or a millisecond later. So a session cut off at an odd tick may
/// have gone along an edge to an effect that has not started, and effects
/// side by side may end in the millisecond others start.
final class _Run {
  _Run(this.program, this.random)
    : routes = [for (final _ in program.functions) {}];

  final _Program program;
  final Random random;
  final List<_Record> records = [];

  /// By function, the index of each edge gone along and when it first was.
  final List<Map<int, int>> routes;

  /// The effects in the order they started, those that started at once in
  /// the order they were called.
  List<_Record> get _ordered => [...records]
    ..sort(
      (a, b) => a.start != b.start
          ? a.start.compareTo(b.start)
          : a.order.compareTo(b.order),
    );

  void start() {
    try {
      _call(0, _Context(null), (at: const [], time: 0, past: 0));
    } on _TooLong {
      records.clear();
    }
  }

  /// The last tick of the run.
  int get last => records.map((r) => r.end).fold(0, max);

  /// The session as far as the journal tells before the tick [cut], or all
  /// of it.
  SessionData session({required String status, required int? cut}) {
    final j = Journal('a1b2-session', workflow: 'f0', snapshot: false);
    for (final r in _ordered) {
      if (cut != null && r.start >= cut) continue;
      j.effect(
        r.name,
        r.start ~/ 2 / 1000,
        end: cut == null || r.end < cut ? r.end ~/ 2 / 1000 : null,
        place: r.place,
        key: r.key,
        after: r.after,
      );
    }
    final end = (cut ?? last + 2) ~/ 2;
    switch (status) {
      case 'finished':
        j.finish(end / 1000);
      case 'failed':
        j.fail(end / 1000, 'StateError: boom');
      case 'interrupted':
        j.processGone();
    }
    return j.data;
  }

  /// The journal before the tick [cut], short, in milliseconds.
  String journal(int? cut) => [
    for (final r in _ordered)
      if (cut == null || r.start < cut)
        '${r.key}<${r.after ?? '-'} ${r.start ~/ 2}-'
            '${cut == null || r.end < cut ? r.end ~/ 2 : ''}',
  ].join(', ');

  /// Calls the function [i] in [context] from [here]: returns where its
  /// caller is when it is done, and the key of the effect it handed on, if
  /// any.
  ({_Here here, String? handed}) _call(int i, _Context context, _Here here) {
    final drawing = program._drawings[i]!;
    _calls[i] = _called[i]++;
    final done = _block(i, program.bodies[i], context, (
      at: [(drawing.entry, null)],
      time: here.time,
      past: here.past,
    ), closure: false);
    _calls.remove(i);
    if (!done.returned) _arrive(i, done.here.at, drawing.exit, done.here.time);
    return (here: done.here, handed: done.handed);
  }

  /// By each function the code is in now, which call of it.
  final Map<int, int> _calls = {};

  /// How many times each function was called.
  late final List<int> _called = [for (final _ in program.functions) 0];

  _Done _block(
    int i,
    List<_Statement> statements,
    _Context context,
    _Here here, {
    required bool closure,
  }) {
    for (final s in statements) {
      final done = _statement(i, s, context, here, closure: closure);
      if (done.returned) return done;
      here = done.here;
    }
    return (here: here, returned: false, handed: null);
  }

  _Done _statement(
    int i,
    _Statement s,
    _Context context,
    _Here here, {
    required bool closure,
  }) {
    final (:at, :time, :past) = here;
    _Done on(_At at, int time, int past) =>
        (here: (at: at, time: time, past: past), returned: false, handed: null);
    switch (s) {
      case _Effect():
        final record = _effect(i, s, context, here);
        context.after = record.key;
        return on([(s.vertex!, null)], _turn(record.end), _with(past, record));
      case _Hidden(:final name, :final handsOn):
        final record = _record(
          name,
          random.nextBool() ? 'lib/retry.dart:$name' : null,
          context.after,
          here,
        );
        if (handsOn) context.after = record.key;
        return on(at, _turn(record.end), _with(past, record));
      case _If(:final then, :final otherwise):
        final yes = random.nextBool();
        return _block(i, yes ? then : otherwise, context, (
          at: _fork(i, s.fork, yes, at, time),
          time: time,
          past: past,
        ), closure: closure);
      case _While(:final body):
        for (var round = 0; ; round++) {
          final yes = round < _rounds && random.nextBool();
          here = (
            at: _fork(i, s.fork, yes, here.at, here.time),
            time: here.time,
            past: here.past,
          );
          if (!yes) return (here: here, returned: false, handed: null);
          final done = _block(i, body, context, here, closure: closure);
          if (done.returned) return done;
          here = done.here;
        }
      case _Call(:final callee):
        _arrive(i, at, s.vertex!, time);
        final called = _call(callee, _Context(context.after), here);
        if (called.handed case final handed?) context.after = handed;
        return on(
          [(s.vertex!, null)],
          _turn(called.here.time),
          called.here.past,
        );
      case _Closure(:final body):
        final inner = _Context(context.after);
        final done = _block(i, body, inner, here, closure: true);
        if (done.handed case final handed?) context.after = handed;
        return on(done.here.at, _turn(done.here.time), done.here.past);
      case _Wait(:final branches):
        var (end, done) = (time, past);
        for (final branch in branches) {
          switch (branch) {
            case _Effect():
              final record = _effect(i, branch, context, here);
              (end, done) = (max(end, record.end), _with(done, record));
            case _Call(:final callee):
              _arrive(i, at, branch.vertex!, time);
              final called = _call(callee, _Context(context.after), here).here;
              (end, done) = (max(end, called.time), done | called.past);
            default:
              throw StateError('a branch is an effect or a call');
          }
        }
        return on(
          [
            for (final branch in branches)
              switch (branch) {
                _Effect(:final vertex) ||
                _Call(:final vertex) => (vertex!, null),
                _ => throw StateError('a branch is an effect or a call'),
              },
          ],
          _turn(end),
          done,
        );
      case _Return(:final tail):
        String? handed;
        if (tail != null) {
          final record = _effect(i, tail, context, here);
          here = (
            at: [(tail.vertex!, null)],
            time: record.end,
            past: _with(past, record),
          );
          handed = record.key;
        }
        if (!closure) {
          _arrive(i, here.at, program._drawings[i]!.exit, here.time);
        }
        return (here: here, returned: true, handed: handed);
    }
  }

  /// The effects done in [past] and [record].
  int _with(int past, _Record record) => past | 1 << record.order;

  /// The code at [at] comes to [fork] and leaves it by [yes] or not; a fork
  /// not drawn is not there.
  _At _fork(int i, _Vertex? fork, bool yes, _At at, int time) {
    final drawing = program._drawings[i]!;
    if (fork == null || drawing.hidden.contains(fork)) return at;
    _arrive(i, at, fork, time);
    return [(fork, yes ? 'true' : 'false')];
  }

  /// The effect [s] called in [context] from [here].
  _Record _effect(int i, _Effect s, _Context context, _Here here) {
    _arrive(i, here.at, s.vertex!, here.time);
    return _record(s.name, _placeOf(s.name), context.after, here);
  }

  /// The turn after an `await` of what is done at [done].
  int _turn(int done) => done + done % 2 + 2 * random.nextInt(2);

  _Record _record(String name, String? place, String? after, _Here here) {
    if (records.length == 40) throw _TooLong();
    final record = (
      order: records.length,
      name: name,
      key: '$name#${records.length + 1}',
      after: after,
      place: place,
      start: here.time + 1,
      end: random.nextInt(4) == 0
          ? here.time + 1
          : here.time + 2 * (1 + random.nextInt(3)),
      past: here.past,
      calls: {..._calls},
    );
    records.add(record);
    return record;
  }

  /// The code at [at] comes to [to] at [time] in the body of function [i].
  void _arrive(int i, _At at, _Vertex to, int time) {
    final drawing = program._drawings[i]!;
    final route = routes[i];
    for (final (from, label) in at) {
      final edge = drawing.edge(from, label, to);
      route[edge] = min(route[edge] ?? time, time);
    }
  }
}

/// A run with too many effects to be small.
final class _TooLong implements Exception {}
