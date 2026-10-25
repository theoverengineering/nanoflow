// Routes (graph node objects design §8–§9): the function a part's `.next`
// takes, read into the points of its graph's body as a workflow function's
// body is. Its `if`, `switch` and `?:` are forks labelled as there; each node
// or graph called in what it returns is an edge to that node, a set an edge
// to each of its nodes, and `null` or the end of its body an edge to the end
// of the graph. A `throw` ends its way: the branch fails.

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
        final fork = _points._fork(label, s.expression, _ifOutcomes);
        _connect(from, fork);
        return [
          ..._statement(s.thenStatement, [(fork, 'true')]),
          ...switch (s.elseStatement) {
            final e? => _statement(e, [(fork, 'false')]),
            null => [(fork, 'false')],
          },
        ];
      case SwitchStatement():
        final (fork, labels, matchesAll) = _points._switchFork(s);
        _connect(from, fork);
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
          final node = element is Expression
              ? _package._nodelikeCalled(element.unParenthesized)
              : null;
          if (node == null) {
            _notRead(element, 'route value not drawn: ${_source(element)}');
            continue;
          }
          final point = _point(node, element);
          _connect(from, point);
          points.add(point);
        }
        _parallels.add(points);
      case SwitchExpression(:final expression, :final cases):
        final labels = [for (final c in cases) _source(c.guardedPattern)];
        final fork = _points._fork(
          'switch (${_source(expression)})',
          expression,
          labels,
        );
        _connect(from, fork);
        for (final (i, c) in cases.indexed) {
          _value(c.expression, [(fork, labels[i])]);
        }
      case ConditionalExpression(
        :final condition,
        :final thenExpression,
        :final elseExpression,
      ):
        final fork = _points._fork(_source(condition), condition, _ifOutcomes);
        _connect(from, fork);
        _value(thenExpression, [(fork, 'true')]);
        _value(elseExpression, [(fork, 'false')]);
      default:
        _notRead(value, 'route value not drawn: ${_source(value)}');
    }
  }

  /// Warns [message] at [node], a route or a part of one that is not read:
  /// where it leads is not known.
  void _notRead(AstNode node, String message) {
    _package._warn(node, message);
    _unread = true;
  }
}
