// Graphs of nodes (graph node objects design §8–§9): a top-level variable
// made by `Graph(name, parts)` of `package:nanoflow` is drawn as a function
// of the graph file, whose body has an effect for a node made by `node(…)`
// in a top-level variable, a call for a graph that is a node, and the forks
// of its routes (routes.dart).

part of 'extract.dart';

/// A node or a graph declared in a top-level variable: what a part of a
/// graph starts from and what a route leads to.
sealed class _Nodelike {
  _Nodelike(this.name, this.variable, this.doc);

  /// The name it is made with; its variable's when that is not a literal.
  final String name;

  final TopLevelVariableElement variable;

  /// The doc comment over its variable ([docText]); `null` without one.
  final String? doc;

  /// `node(…)` or `Graph(…)`.
  Expression get made;

  /// What it gives: the `O` of the `Node<I, O>` or the `Graph<I, O>` its
  /// variable is; `null` when not known.
  DartType? get output => switch (variable.type) {
    InterfaceType(typeArguments: [_, final output]) => output,
    _ => null,
  };
}

/// A node made by `node(…)`: drawn as an effect.
final class _NodeDeclaration extends _Nodelike {
  _NodeDeclaration(super.name, super.variable, super.doc, this.made);

  @override
  final MethodInvocation made;
}

/// A graph: drawn as a function, and as a call where it is a node.
final class _GraphDeclaration extends _Nodelike {
  _GraphDeclaration(
    super.name,
    super.variable,
    super.doc,
    this.made, {
    required this.id,
    required this.place,
  });

  @override
  final InstanceCreationExpression made;

  /// `path#variable`.
  final String id;

  /// `path:line` of the name of the variable.
  final String place;
}

/// Whether [e] makes a `Graph` of `package:nanoflow`.
bool _makesGraph(InstanceCreationExpression e) =>
    _isNanoflowClass(e.constructorName.element?.enclosingElement, 'Graph');

/// Whether [e] makes a node with `node` of `package:nanoflow`.
bool _makesNode(MethodInvocation e) {
  final function = e.methodName.element;
  return function is TopLevelFunctionElement &&
      function.name == 'node' &&
      function.library.uri.toString().startsWith('package:nanoflow/');
}

/// Whether [element] is the class [name] of `package:nanoflow`.
bool _isNanoflowClass(Element? element, String name) =>
    element is ClassElement &&
    element.name == name &&
    element.library.uri.toString().startsWith('package:nanoflow/');

/// Whether [node] calls the method [name] of the class [type] of
/// `package:nanoflow`.
bool _isNanoflowMethod(MethodInvocation node, String type, String name) {
  final method = node.methodName.element;
  return node.methodName.name == name &&
      method is MethodElement &&
      _isNanoflowClass(method.enclosingElement, type);
}

/// Whether [type] is known enough to check: not `null`, not `dynamic`.
bool _known(DartType? type) => type != null && type is! DynamicType;

extension on _Package {
  /// Finds the node or the graph made in [variable], a top-level variable
  /// whose declaration has the doc comment [comment].
  void _declareNodelike(VariableDeclaration variable, Comment? comment) {
    final made = variable.initializer?.unParenthesized;
    final element = variable.declaredFragment?.element;
    if (element is! TopLevelVariableElement) return;
    final doc = comment == null ? null : docText(comment.tokens);
    switch (made) {
      case InstanceCreationExpression() when _makesGraph(made):
        _nodelikes[element.baseElement] = _GraphDeclaration(
          _nameIn(made, made.argumentList, variable, 'graph'),
          element,
          doc,
          made,
          id: '${_paths[variable.root]}#${variable.name.lexeme}',
          place: _place(variable, offset: variable.name.offset),
        );
      case MethodInvocation() when _makesNode(made):
        _nodelikes[element.baseElement] = _NodeDeclaration(
          _nameIn(made, made.argumentList, variable, 'node'),
          element,
          doc,
          made,
        );
      default:
    }
  }

  /// The name [made], a [kind], takes first in [arguments]: a string
  /// literal; or, which it warns of, the name of its [variable].
  String _nameIn(
    Expression made,
    ArgumentList arguments,
    VariableDeclaration variable,
    String kind,
  ) {
    if (arguments.arguments.firstOrNull case StringLiteral(
      :final stringValue?,
    )) {
      return stringValue;
    }
    _warn(made, '$kind name is not a string literal');
    return variable.name.lexeme;
  }

  /// Whether [made], `node(…)` or `Graph(…)`, is in a top-level variable.
  bool _isDeclared(Expression made) =>
      _nodelikes.values.any((declared) => identical(declared.made, made));

  /// The node or the graph declared in the sources that [element] refers
  /// to: the variable or its getter; `null` for anything else.
  _Nodelike? _nodelikeOf(Element? element) => switch (element) {
    GetterElement(:final variable) => _nodelikes[variable.baseElement],
    TopLevelVariableElement() => _nodelikes[element.baseElement],
    _ => null,
  };

  /// The node or the graph [expression] names; `null` for anything else.
  _Nodelike? _nodelikeIn(Expression? expression) =>
      switch (expression?.unParenthesized) {
        Identifier(:final element) => _nodelikeOf(element),
        _ => null,
      };

  /// The node or the graph [node] calls, which gives the transition to it —
  /// `inspect(change)`, the implicit `call` of the variable, or
  /// `inspect.call(change)` —; `null` when it calls none.
  _Nodelike? _nodelikeCalled(AstNode node) => switch (node) {
    FunctionExpressionInvocation(:final function) => _nodelikeIn(function),
    MethodInvocation(target: null, :final methodName) => _nodelikeOf(
      methodName.element,
    ),
    MethodInvocation(:final target?, :final methodName)
        when methodName.name == 'call' =>
      _nodelikeIn(target),
    _ => null,
  };

  /// The graph [expression] names; `null` for anything else.
  _GraphDeclaration? _graphIn(Expression? expression) =>
      switch (_nodelikeIn(expression)) {
        final _GraphDeclaration graph => graph,
        _ => null,
      };

  /// The graphs of the sources, each drawn as a function, by id; and the
  /// bodies of their routes, whose side effects outside effects warn.
  ///
  /// Warns of a graph that is a node of another graph and can end in
  /// several ends at once (graph node objects design §6).
  (Map<String, GraphFunction>, Set<FunctionBody>) _drawGraphs() {
    final bodies = [for (final graph in _graphs) _GraphBody(this, graph)];
    final functions = {
      for (final body in bodies)
        body.graph.id: GraphFunction(
          id: body.graph.id,
          name: body.graph.name,
          place: body.graph.place,
          doc: body.graph.doc,
          body: body.build(),
        ),
    };
    for (final body in bodies) {
      final isNode = bodies.any(
        (other) => other != body && other.nodes.contains(body.graph),
      );
      if (isNode && body.endsAtOnce) {
        _warn(
          body.graph.made,
          'graph ${body.graph.name} is a node and can end in several ends '
          'at once',
        );
      }
    }
    return (functions, {for (final body in bodies) ...body.routes});
  }
}

/// The body of one graph, read from its parts: the point of each node, where
/// the declaration first names it, and the forks of the routes.
final class _GraphBody {
  _GraphBody(this._package, this.graph) : _points = _Points(_package);

  final _Package _package;
  final _GraphDeclaration graph;

  /// The points of the body and the ways between them.
  final _Points _points;

  /// The point of each node of the graph, with where the declaration first
  /// names it.
  final _made = <_Nodelike, (_Drawn, AstNode)>{};

  /// The nodes whose output goes somewhere: they have arrows, or are in a
  /// join.
  final _going = <_Nodelike>{};

  /// The points the graph starts at.
  final _starts = <_V>[];

  /// The points each set a route gives leads to, side by side.
  final _parallels = <List<_V>>[];

  /// The bodies of the routes read.
  final routes = <FunctionBody>{};

  /// Whether a part, a route or what one gives could not be read: where it
  /// leads is not known.
  var _unread = false;

  /// The nodes and graphs that are nodes of this graph.
  Iterable<_Nodelike> get nodes => _made.keys;

  GraphBody build() {
    final parts = graph.made.argumentList.arguments
        .where((argument) => argument is! NamedArgument)
        .elementAtOrNull(1)
        ?.argumentExpression;
    if (parts case ListLiteral(:final elements)) {
      for (final element in elements) {
        if (element is! Expression || !_part(element)) {
          _notRead(element, 'graph part not drawn: ${_source(element)}');
        }
      }
    }
    // A node without arrows of its own, and not in a join, ends its branch.
    for (final MapEntry(key: node, value: (point, _)) in _made.entries) {
      if (!_going.contains(node)) _connect([(point, null)], _points._exit);
    }
    _warnUnreached();
    return _points._emit(roots: [for (final (point, _) in _made.values) point]);
  }

  /// Reads the part [e] — `Graph.start(…)`, `Graph.part(…)` or
  /// `Graph.join([…])`, and the `.next(…)` after it —; `false` when it is
  /// none of them, or its nodes are not nodes declared in the sources.
  bool _part(Expression e) {
    var head = e;
    Expression? route;
    if (e case MethodInvocation(:final target?)
        when _isNanoflowMethod(e, 'Part', 'next')) {
      head = target;
      route = _firstPositional(e.argumentList);
    }
    if (head is! MethodInvocation) return false;
    final argument = _firstPositional(head.argumentList);
    final start = _isNanoflowMethod(head, 'Graph', 'start');
    if (start || _isNanoflowMethod(head, 'Graph', 'part')) {
      final node = _package._nodelikeIn(argument);
      if (node == null) return false;
      final point = _point(node, argument!);
      if (start) {
        _starts.add(point);
        _connect([(_points._entry, null)], point);
      }
      if (route != null) {
        _going.add(node);
        _route(route, [(point, null)]);
      }
      return true;
    }
    if (_isNanoflowMethod(head, 'Graph', 'join') && argument is ListLiteral) {
      final members = <(_Nodelike, Expression)>[];
      for (final element in argument.elements) {
        if (element is! Expression) return false;
        final node = _package._nodelikeIn(element);
        if (node == null) return false;
        members.add((node, element));
      }
      final join = _points._join();
      for (final (node, element) in members) {
        _going.add(node);
        _connect([(_point(node, element), null)], join);
      }
      if (route == null) {
        // Its record is the result.
        _connect([(join, null)], _points._exit);
      } else {
        _checkJoin(
          [for (final (node, _) in members) node],
          _route(route, [(join, null)]),
          route,
        );
      }
      return true;
    }
    return false;
  }

  /// The point of [node] in this graph, made where [mention] first names it.
  _Drawn _point(_Nodelike node, AstNode mention) {
    if (_made[node] case (final point, _)) return point;
    if (_made.keys.any((other) => other.name == node.name)) {
      _package._warn(
        mention,
        'two nodes are named ${node.name} in graph ${graph.name}',
      );
    }
    final place = _package._place(mention);
    final point = _points._add<_Drawn>(switch (node) {
      _NodeDeclaration() => _Effect(node.name, place, node.doc),
      _GraphDeclaration(:final id) => _Call([id], place),
    });
    _made[node] = (point, mention);
    return point;
  }

  /// Warns at [route], the route of the join of [members], when [takes],
  /// what it takes, is not the record of their outputs in their order.
  void _checkJoin(List<_Nodelike> members, DartType? takes, AstNode route) {
    if (!_known(takes)) return;
    final types = _package._libraryOf[graph.made.root]!.typeSystem;
    bool fits(RecordType record) {
      if (record.namedFields.isNotEmpty ||
          record.positionalFields.length != members.length) {
        return false;
      }
      for (final (i, member) in members.indexed) {
        final output = member.output;
        if (_known(output) &&
            !types.isAssignableTo(output!, record.positionalFields[i].type)) {
          return false;
        }
      }
      return true;
    }

    if (takes is RecordType && fits(takes)) return;
    _package._warn(
      route,
      'the route of the join takes ${takes!.getDisplayString()}, not the '
      "record of its nodes' outputs",
    );
  }

  /// Warns of each node that no way from the starts reaches; not when a
  /// part or a route could not be read, which may lead to it.
  void _warnUnreached() {
    if (_unread) return;
    final reached = _reachedFrom(_points._entry, pastJoins: true);
    for (final MapEntry(key: node, value: (point, mention)) in _made.entries) {
      if (!reached.contains(point)) {
        _package._warn(mention, '${node.name} cannot be reached');
      }
    }
  }

  /// Whether the graph can end in several ends at once: two or more of its
  /// starts, or of the points a set leads to, each reach the end without
  /// passing a join.
  bool get endsAtOnce => [
    _starts,
    ..._parallels,
  ].any((points) => points.where(_endsBeforeJoin).length > 1);

  /// Whether a way from [point] reaches the end without passing a join.
  bool _endsBeforeJoin(_V point) =>
      _reachedFrom(point, pastJoins: false).contains(_points._exit);

  /// The points the ways from [from] reach, [from] too; past a join only
  /// when [pastJoins].
  Set<_V> _reachedFrom(_V from, {required bool pastJoins}) {
    final reached = <_V>{};
    for (final queue = [from]; queue.isNotEmpty;) {
      final v = queue.removeLast();
      if (!reached.add(v) || (v is _Join && !pastJoins)) continue;
      queue.addAll([
        for (final (_, to) in _points._edges[v] ?? const <(String?, _V)>[]) to,
      ]);
    }
    return reached;
  }

  void _connect(List<_Out> from, _V to) => _points._connect(from, to);

  String _source(AstNode node) => _package._source(node);
}
