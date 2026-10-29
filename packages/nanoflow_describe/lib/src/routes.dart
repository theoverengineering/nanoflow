// Routes (graph node objects design §8–§9): the function a part's `.next`
// takes, read into the points of its graph's body as a workflow function's
// body is. Its `if`, `switch` and `?:` are forks labelled as there — but a
// `switch` the route decides by first, right after the node it follows, is no
// fork: its cases are that node's own exits, so a node that ends several ways
// is one tile with an exit for each. So is an `if` or a `?:` it decides by
// first: its exits are the condition and `else`, and an `if` or a `?:` that
// `else` decides by — an else-if — adds its condition before it. Unless they
// all lead to the same place: then the node has an arrow, as a fork that
// decides nothing is not drawn. Each node or graph called in what it
// returns is an edge to that node, a set an edge to each of its nodes — a
// `for` element in it a fork labelled as a loop, whose `each` goes to its
// node —, and `null` or the end of its body an edge to the end of the graph. A `throw`
// ends its way: the branch fails. A route that is async or a generator is not
// read: it gives a Future or an Iterable, no Next.

part of 'extract.dart';

extension on _GraphBody {
  /// Reads [route], what `.next` takes — a function literal, or a top-level
  /// function of the sources —, from [from], the node or the join it
  /// follows. Gives the type of what it takes; `null` when not known, or
  /// when it cannot be read, which it warns of.
  DartType? _route(Expression route, List<_Out> from) {
    final (body, takes) = switch (route.unParenthesized) {
      FunctionExpression(:final body, :final declaredFragment) => (
        body,
        declaredFragment?.element.formalParameters.firstOrNull?.type,
      ),
      Identifier(:final element) when element is TopLevelFunctionElement => (
        _package._declarations[element.baseElement]?.body,
        element.formalParameters.firstOrNull?.type,
      ),
      _ => (null, null),
    };
    if (body == null) {
      _notRead(route, 'route not drawn: ${_source(route)}');
      return null;
    }
    // An async route gives a Future, a generator an Iterable, and neither is
    // a Next, a set of them or null: the graph fails as it runs, and there
    // is nothing to draw.
    if (body.isAsynchronous || body.isGenerator) {
      _notRead(route, 'route is async or a generator: ${_source(route)}');
      return null;
    }
    routes.add(body);
    switch (body) {
      case ExpressionFunctionBody(:final expression):
        _value(expression, from);
      case BlockFunctionBody(:final block):
        // The end of the body gives null: the branch ends.
        _connect(_statement(block, from), _points._exit);
      default:
    }
    return takes;
  }

  /// Reads the statement [s] of a route from [from]; gives the ways out of
  /// it that go on after it: none after a `return` or a `throw`. A statement
  /// with neither in it decides nothing and is passed by.
  List<_Out> _statement(Statement s, List<_Out> from) {
    if (from.isEmpty || !_leavesIn(s)) return from;
    switch (s) {
      case Block(:final statements):
        return _statements(statements, from);
      case ReturnStatement(:final expression):
        if (expression == null) {
          _connect(from, _points._exit);
        } else {
          _value(expression, from);
        }
        return const [];
      case ExpressionStatement(expression: ThrowExpression()):
        return const [];
      case IfStatement():
        final label = switch (s.caseClause) {
          final c? => '${_source(s.expression)} ${_source(c)}',
          null => _source(s.expression),
        };
        final (fork, yes, no) = _ifFork(label, s.expression, from);
        return [
          ..._statement(s.thenStatement, [(fork, yes)]),
          ...switch (s.elseStatement) {
            final e? => _statement(e, [(fork, no)]),
            null => [(fork, no)],
          },
        ];
      case SwitchStatement():
        final (made, labels, matchesAll) = _points._switchFork(s);
        // A fork not used is reached by nothing, and not drawn.
        final fork = _exitsOf(from) ?? made;
        if (identical(fork, made)) _connect(from, fork);
        final exits = <_Out>[];
        // Cases with no statements of their own share the body of the next
        // one.
        final pending = <String>[];
        for (final (i, member) in s.members.indexed) {
          pending.add(labels[i]);
          if (member.statements.isEmpty) continue;
          exits.addAll(
            _statements(member.statements, [
              for (final label in pending) (fork, label),
            ]),
          );
          pending.clear();
        }
        return [
          ...exits,
          for (final label in pending) (fork, label),
          if (!matchesAll) (fork, 'default'),
        ];
      default:
        _notRead(s, 'route not drawn: ${_source(s)}');
        return from;
    }
  }

  List<_Out> _statements(Iterable<Statement> statements, List<_Out> from) {
    var current = from;
    for (final statement in statements) {
      current = _statement(statement, current);
    }
    return current;
  }

  /// Whether a `return` or a `throw` statement in [s], not in a function
  /// in it, leaves the route.
  bool _leavesIn(Statement s) {
    var leaves = false;
    void visit(AstNode node) {
      if (leaves || node is FunctionExpression) return;
      if (node is ReturnStatement ||
          node is ExpressionStatement && node.expression is ThrowExpression) {
        leaves = true;
        return;
      }
      node.childEntities.whereType<AstNode>().forEach(visit);
    }

    visit(s);
    return leaves;
  }

  /// Reads [e], what a route gives, from [from]: a node or a graph called is
  /// an edge to it, a set an edge to each of its nodes, `null` an edge to
  /// the end; a `switch` and `?:` are forks, and each of their values is
  /// read in turn.
  void _value(Expression e, List<_Out> from) {
    final value = e.unParenthesized;
    if (_package._nodelikeCalled(value) case final node?) {
      _connect(from, _point(node, value));
      return;
    }
    // The branch fails: no edge leaves.
    if (value is ThrowExpression) return;
    switch (value) {
      case NullLiteral():
        _connect(from, _points._exit);
      case SetOrMapLiteral(isSet: true, :final elements):
        final points = <_V>[];
        for (final element in elements) {
          // A `for` element runs its node once per item, all at once.
          final loop = element is ForElement ? element : null;
          final called = loop?.body ?? element;
          final node = called is Expression
              ? _package._nodelikeCalled(called.unParenthesized)
              : null;
          if (node == null) {
            _notRead(element, 'route value not drawn: ${_source(element)}');
            continue;
          }
          if (loop == null) {
            final point = _point(node, called);
            _connect(from, point);
            points.add(point);
            continue;
          }
          // A fork labelled as a loop is, whose `each` goes to the node; its
          // copies may end at once, as two nodes of a set may. Its `done` has
          // no edge — when the items run out, this element starts nothing
          // more —, so the fork is drawn though `each` is its only way.
          final fork = _points._fork(
            _loopLabel(loop.forLoopParts),
            loop,
            const ['each', 'done'],
          );
          final point = _point(node, called);
          _connect(from, fork);
          _connect([(fork, 'each')], point);
          points.addAll([point, point]);
        }
        _parallels.add(points);
      case SwitchExpression(:final expression, :final cases):
        final labels = [
          for (final c in cases) _caseLabel(c.guardedPattern, _source),
        ];
        final _V fork;
        if (_exitsOf(from) case final node?) {
          fork = node;
        } else {
          fork = _points._fork(
            'switch (${_source(expression)})',
            expression,
            labels,
          );
          _connect(from, fork);
        }
        for (final (i, c) in cases.indexed) {
          _value(c.expression, [(fork, labels[i])]);
        }
      case ConditionalExpression(
        :final condition,
        :final thenExpression,
        :final elseExpression,
      ):
        final (fork, yes, no) = _ifFork(_source(condition), condition, from);
        _value(thenExpression, [(fork, yes)]);
        _value(elseExpression, [(fork, no)]);
      default:
        _notRead(value, 'route value not drawn: ${_source(value)}');
    }
  }

  /// The label of a loop's fork: `for x in xs` as a `for` statement's, or
  /// the parts as written, `for (var i = 0; i < n; i++)`.
  String _loopLabel(ForLoopParts parts) => switch (parts) {
    final ForEachParts each =>
      'for ${_points._loopVariable(each)} in ${_source(each.iterable)}',
    _ => 'for (${_source(parts)})',
  };

  /// The fork of an `if` or a `?:` on [condition], labelled [label], that
  /// comes [from], and the outcomes it goes on by when the condition holds
  /// and when not: the condition and `else` when it is the exits of the node
  /// the route follows, or of such a fork it is the `else` of; `true` and
  /// `false` anywhere else.
  (_Fork, String, String) _ifFork(
    String label,
    Expression condition,
    List<_Out> from,
  ) {
    final exitsOf = switch (from) {
      [(final _Fork fork, 'else')] when fork.exitsOf != null => fork,
      _ => _exitsOf(from),
    };
    final (yes, no) = exitsOf == null ? ('true', 'false') : (label, 'else');
    final fork = _points._fork(label, condition, [yes, no], exitsOf: exitsOf);
    _connect(from, fork);
    return (fork, yes, no);
  }

  /// The node a `switch` that comes [from] it goes out of by its own exits:
  /// the node the route follows, when the route decides by the switch first;
  /// `null` after a join, a fork or anything else.
  _V? _exitsOf(List<_Out> from) => switch (from) {
    [(final _V node, null)] when node is _Effect || node is _Call => node,
    _ => null,
  };

  /// Warns [message] at [node], a route or a part of one that is not read:
  /// where it leads is not known.
  void _notRead(AstNode node, String message) {
    _package._warn(node, message);
    _unread = true;
  }
}
