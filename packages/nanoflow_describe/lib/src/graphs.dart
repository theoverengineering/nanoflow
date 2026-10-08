// Graphs of nodes (graph design §9, §10): a top-level variable made by
// `Graph(name, parts)` of `package:nanoflow` is drawn as a function of the
// graph file, whose body has the nodes a workflow function's has — an effect
// for a node that is a function of one parameter, a call for a workflow
// function or a graph, a fork for each map of targets —, so the UI draws it
// as it is.

part of 'extract.dart';

/// A graph declared in a top-level variable of the sources.
final class _GraphDeclaration {
  _GraphDeclaration(this.id, this.name, this.place, this.variable, this.made);

  /// `path#variable`.
  final String id;

  /// The name the graph is made with; its variable's when that is not a
  /// literal.
  final String name;

  /// `path:line` of the name of the variable.
  final String place;

  final TopLevelVariableElement variable;

  /// `Graph(…)`.
  final InstanceCreationExpression made;
}

/// Whether [e] makes a `Graph` of `package:nanoflow`.
bool _makesGraph(InstanceCreationExpression e) =>
    _isNanoflowClass(e.constructorName.element?.enclosingElement, 'Graph');

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

extension on _Package {
  /// Finds the graph made in [variable], a top-level variable of [unit].
  void _declareGraph(VariableDeclaration variable) {
    final made = variable.initializer?.unParenthesized;
    final element = variable.declaredFragment?.element;
    if (made is! InstanceCreationExpression ||
        !_makesGraph(made) ||
        element is! TopLevelVariableElement) {
      return;
    }
    final name = switch (made.argumentList.arguments.firstOrNull) {
      SimpleStringLiteral(:final value) => value,
      _ => null,
    };
    if (name == null) {
      _warn(made, 'graph name is not a string literal');
    }
    _graphs[element.baseElement] = _GraphDeclaration(
      '${_paths[variable.root]}#${variable.name.lexeme}',
      name ?? variable.name.lexeme,
      _place(variable, offset: variable.name.offset),
      element,
      made,
    );
  }

  /// The graph declared in the sources that [element] refers to: the
  /// variable or its getter; `null` for anything else.
  _GraphDeclaration? _graphOf(Element? element) => switch (element) {
    GetterElement(:final variable) => _graphs[variable.baseElement],
    TopLevelVariableElement() => _graphs[element.baseElement],
    _ => null,
  };

  /// The graph [expression] refers to — `review`, `review.call` or the
  /// implicit `call` of `review` —; `null` for anything else.
  _GraphDeclaration? _graphReferenced(Expression? expression) =>
      switch (expression?.unParenthesized) {
        ImplicitCallReference(:final expression) => _graphReferenced(
          expression,
        ),
        PrefixedIdentifier(:final prefix, :final identifier)
            when identifier.name == 'call' =>
          _graphReferenced(prefix),
        PropertyAccess(:final target, :final propertyName)
            when propertyName.name == 'call' =>
          _graphReferenced(target),
        Identifier(:final element) => _graphOf(element),
        _ => null,
      };

  /// The graph [node] calls — `review(f, input)` or `review.call(f, input)`
  /// —; `null` when it calls none.
  _GraphDeclaration? _graphCalled(AstNode node) => switch (node) {
    FunctionExpressionInvocation(:final function) => _graphReferenced(function),
    MethodInvocation(target: null, :final methodName) => _graphOf(
      methodName.element,
    ),
    MethodInvocation(:final target?, :final methodName)
        when methodName.name == 'call' =>
      _graphReferenced(target),
    _ => null,
  };
}

/// Where a part of a graph is: at a node, or at a join.
sealed class _At {}

/// A node of the body: its id, the name a fork after it is labelled with,
/// and the types of its input and its output, when known.
final class _AtNode extends _At {
  _AtNode(this.id, this.name, this.input, this.output);

  final String id;
  final String name;
  final DartType? input;
  final DartType? output;
}

final class _AtJoin extends _At {
  _AtJoin(this.sources);

  final List<_AtNode> sources;
}

/// The body of one graph.
final class _GraphBody {
  _GraphBody(this._package, this._graph);

  final _Package _package;
  final _GraphDeclaration _graph;

  final _nodes = <GraphNode>[];

  /// The nodes made so far, by the function or the graph.
  final _made = <Object, _AtNode>{};

  final _edges = <GraphEdge>[];
  final _seen = <(String?, String?, String?)>{};

  /// The nodes whose output goes somewhere: they have arrows, or are in a
  /// join.
  final _going = <String>{};

  GraphBody build() {
    final parts = _graph.made.argumentList.arguments
        .where((argument) => argument is! NamedArgument)
        .elementAtOrNull(1)
        ?.argumentExpression;
    if (parts case ListLiteral(:final elements)) {
      for (final element in elements) {
        if (element is Expression) {
          _part(element);
        } else {
          _package._warn(element, 'graph part not drawn: ${_source(element)}');
        }
      }
    }
    for (final node in _made.values) {
      if (!_going.contains(node.id)) _edge(node.id, null);
    }
    return GraphBody(nodes: _nodes, edges: _edges);
  }

  /// Where the part [e] — `Graph.start(…)`, `Graph.part(…)`,
  /// `Graph.join([…])` and the `.next(…)` after them — is after its arrows;
  /// `null` when it ends at a set or a map, or cannot be read.
  _At? _part(Expression e) {
    if (e case MethodInvocation(:final target?)
        when _isNanoflowMethod(e, 'Part', 'next')) {
      final at = _part(target);
      if (at == null) return null;
      final arguments = e.argumentList.arguments;
      final to = _firstPositional(e.argumentList);
      final otherwise = [
        for (final argument in arguments)
          if (argument
              case NamedArgument(:final name, :final argumentExpression)
              when name.lexeme == 'otherwise')
            argumentExpression,
      ].firstOrNull;
      if (to == null) return null;
      return _arrow(at, to, otherwise);
    }
    if (e is MethodInvocation) {
      final argument = _firstPositional(e.argumentList);
      if (_isNanoflowMethod(e, 'Graph', 'start') && argument != null) {
        final start = _node(argument);
        if (start != null) _edge(null, start.id);
        return start;
      }
      if (_isNanoflowMethod(e, 'Graph', 'part') && argument != null) {
        return _node(argument);
      }
      if (_isNanoflowMethod(e, 'Graph', 'join') && argument is ListLiteral) {
        final sources = [
          for (final element in argument.elements)
            if (element is Expression) _node(element),
        ];
        if (sources.contains(null)) return null;
        final join = _AtJoin(sources.cast());
        _going.addAll([for (final source in join.sources) source.id]);
        return join;
      }
    }
    _package._warn(e, 'graph part not drawn: ${_source(e)}');
    return null;
  }

  /// Draws the arrows from [at] to [to], with the [otherwise] of a map; gives
  /// the node the part goes on at, `null` after a set or a map.
  _At? _arrow(_At at, Expression to, Expression? otherwise) {
    final target = to.unParenthesized;
    if (at is _AtNode) _going.add(at.id);
    if (target is SetOrMapLiteral && target.isMap) {
      if (at is! _AtNode) {
        _package._warn(target, 'a join leads to a node or a set');
        return null;
      }
      final fork = _add(
        (id) => ConditionNode(
          id: id,
          place: _package._place(target),
          label: 'switch (${at.name})',
        ),
      );
      _edge(at.id, fork);
      final keys = <Expression>[];
      for (final entry in target.elements.whereType<MapLiteralEntry>()) {
        keys.add(entry.key);
        final payload = _keyPayload(at, entry.key);
        for (final (node, written) in _targets(entry.value)) {
          _edge(fork, node.id, _source(entry.key));
          if (payload case (:final type)) _check(type, at, node, written);
        }
      }
      if (otherwise != null) {
        for (final (node, written) in _targets(otherwise)) {
          _edge(fork, node.id, 'otherwise');
          _check(at.output, at, node, written);
        }
      } else if (!_coversAll(at.output, keys)) {
        _edge(fork, null, 'otherwise');
      }
      return null;
    }
    final targets = _targets(target);
    switch (at) {
      case _AtNode():
        for (final (node, written) in targets) {
          _edge(at.id, node.id);
          _check(at.output, at, node, written);
        }
      case _AtJoin(:final sources):
        for (final (node, written) in targets) {
          for (final source in sources) {
            _edge(source.id, node.id);
          }
          _checkJoin(sources, node, written);
        }
    }
    if (target is SetOrMapLiteral || targets.length != 1) return null;
    return targets.single.$1;
  }

  TypeSystem get _types => _package._libraryOf[_graph.made.root]!.typeSystem;

  /// Warns at [written] when [payload], what [source] sends [target], is not
  /// what [target] takes: its input, or [takes], the field of it [source]
  /// fills.
  void _check(
    DartType? payload,
    _AtNode source,
    _AtNode target,
    AstNode written, {
    DartType? takes,
  }) {
    final input = takes ?? target.input;
    if (!_known(payload) || !_known(input)) return;
    if (!_types.isAssignableTo(payload!, input!)) {
      _package._warn(
        written,
        '${target.name} takes ${target.input!.getDisplayString()}, not the '
        '${payload.getDisplayString()} of ${source.name}',
      );
    }
  }

  /// Warns at [written] when [target] does not take the record of the
  /// outputs of [sources], its join.
  void _checkJoin(List<_AtNode> sources, _AtNode target, AstNode written) {
    final input = target.input;
    if (!_known(input)) return;
    if (input case RecordType(:final positionalFields, namedFields: [])
        when positionalFields.length == sources.length) {
      for (final (i, source) in sources.indexed) {
        _check(
          source.output,
          source,
          target,
          written,
          takes: positionalFields[i].type,
        );
      }
      return;
    }
    _package._warn(
      written,
      '${target.name} takes ${input!.getDisplayString()}, not the record of '
      'its join',
    );
  }

  /// What the key [key] of a map of targets after [at] gives its targets: the
  /// second field of a record of two, the value of an Exit, or what it
  /// matches; `null` when it never matches, which it warns of.
  ({DartType? type})? _keyPayload(_AtNode at, Expression key) {
    final output = at.output;
    final second = switch (output) {
      RecordType(positionalFields: [_, final second], namedFields: []) =>
        second.type,
      _ => null,
    };
    final subject = _subjectOf(output);
    final keyElement = _keyElement(key);
    final isType =
        keyElement is InterfaceElement &&
        (key.unParenthesized is TypeLiteral ||
            key.unParenthesized is Identifier);
    final DartType? keyType = isType ? keyElement.thisType : key.staticType;
    if (_known(subject) && _known(keyType)) {
      final matches = isType
          ? _types.isSubtypeOf(keyType!, subject!)
          : _types.isAssignableTo(keyType!, subject!);
      if (!matches) {
        _package._warn(
          key,
          'key ${_source(key)} never matches: switch (${at.name}) takes '
          '${subject.getDisplayString()}',
        );
        return null;
      }
    }
    if (second != null) return (type: second);
    if (isType) return (type: _exitValue(keyType) ?? keyType);
    return (type: key is NullLiteral ? keyType : subject);
  }

  /// The nodes of [e], a node or a set of nodes, each with where it is
  /// written.
  List<(_AtNode, Expression)> _targets(Expression e) {
    final target = e.unParenthesized;
    return [
      for (final written
          in target is SetOrMapLiteral && target.isSet
              ? target.elements.whereType<Expression>()
              : [target])
        if (_node(written) case final node?) (node, written),
    ];
  }

  /// The node [e] refers to, made the first time: a function of one
  /// parameter is an effect, a workflow function or a graph a call.
  _AtNode? _node(Expression e) {
    final element = switch (e.unParenthesized) {
      Identifier(:final element) => element,
      PropertyAccess(:final propertyName) => propertyName.element,
      _ => null,
    };
    // `judged.call`, as flow.start takes a graph, is the graph too.
    final graph = _package._graphReferenced(e) ?? _package._graphOf(element);
    final Object? key = graph ?? element?.baseElement;
    if (_made[key] case final known?) return known;
    final place = _graph.place;
    if (graph != null) {
      final type = graph.variable.type;
      final arguments = type is InterfaceType && type.typeArguments.length == 2
          ? type.typeArguments
          : null;
      return _make(
        graph,
        graph.name,
        arguments?[0],
        arguments?[1],
        (id) => CallNode(id: id, place: place, functions: [graph.id]),
      );
    }
    if (element is ExecutableElement && element is! PropertyAccessorElement) {
      final parameters = element.formalParameters;
      final name = element.name ?? _source(e);
      final output = _awaited(element.returnType);
      if (parameters.length == 2 && _isFlowType(parameters.first.type)) {
        final declaration = _package._declarations[element.baseElement];
        if (declaration != null) _package._nodeFunctions.add(declaration);
        return _make(
          element.baseElement,
          name,
          parameters[1].type,
          output,
          (id) => CallNode(id: id, place: place, functions: [?declaration?.id]),
        );
      }
      if (parameters.length == 1) {
        return _make(
          element.baseElement,
          name,
          parameters.single.type,
          output,
          (id) => EffectNode(id: id, place: place, name: name),
        );
      }
    }
    _package._warn(
      e,
      'graph node is not a top-level function, a static method or a '
      'graph: ${_source(e)}',
    );
    return null;
  }

  _AtNode _make(
    Object key,
    String name,
    DartType? input,
    DartType? output,
    GraphNode Function(String id) node,
  ) => _made[key] = _AtNode(_add(node), name, input, output);

  /// Adds the node [node] makes with the next id, and gives the id.
  String _add(GraphNode Function(String id) node) {
    final id = '${_nodes.length + 1}';
    _nodes.add(node(id));
    return id;
  }

  void _edge(String? from, String? to, [String? label]) {
    if (_seen.add((from, to, label))) {
      _edges.add(GraphEdge(from: from, to: to, label: label));
    }
  }

  String _source(AstNode node) => _package._source(node);
}

/// The type of the value [type], which a function returns, is of: a future's
/// value for a `Future` or a `FutureOr`.
DartType _awaited(DartType type) =>
    type is InterfaceType &&
        (type.isDartAsyncFuture || type.isDartAsyncFutureOr) &&
        type.typeArguments.length == 1
    ? type.typeArguments.single
    : type;

/// Whether [type] is known enough to check: not `null`, not `dynamic`.
bool _known(DartType? type) => type != null && type is! DynamicType;

/// The type of the value of an Exit [type] is: `Change` for a class that
/// extends `Exit<Change>`; `null` for a type that is no Exit.
DartType? _exitValue(DartType? type) {
  if (type is! InterfaceType) return null;
  for (final supertype in [type, ...type.element.allSupertypes]) {
    if (_isNanoflowClass(supertype.element, 'Exit')) {
      return supertype.typeArguments.firstOrNull;
    }
  }
  return null;
}

/// The type the keys of a map of targets are matched against, for an output
/// of [output]: the first field of a record of two, or the output itself.
DartType? _subjectOf(DartType? output) => switch (output) {
  RecordType(positionalFields: [final key, _], namedFields: []) => key.type,
  _ => output,
};

/// Whether [keys] match every value of the subject of [output]: `true` and
/// `false` of a `bool`, every value of an enum, every class that is not
/// abstract under a sealed class.
bool _coversAll(DartType? output, List<Expression> keys) {
  final subject = _subjectOf(output);
  if (subject == null || subject.nullabilitySuffix != NullabilitySuffix.none) {
    return false;
  }
  if (subject.isDartCoreBool) {
    final values = {
      for (final key in keys)
        if (key case BooleanLiteral(:final value)) value,
    };
    return values.length == 2;
  }
  final element = subject.element;
  if (element is EnumElement) {
    final named = {
      for (final key in keys)
        if (_keyElement(key) case GetterElement(
          variable: FieldElement(isEnumConstant: true, :final name?),
        ))
          name,
    };
    return element.constants.every((constant) => named.contains(constant.name));
  }
  if (element is ClassElement && element.isSealed) {
    final named = {
      for (final key in keys)
        if (_keyElement(key) case final ClassElement type) type.baseElement,
    };
    final concrete = [
      for (final type in element.library.classes)
        if (!type.isAbstract &&
            type.allSupertypes.any((s) => s.element == element))
          type.baseElement,
    ];
    return concrete.every(named.contains);
  }
  return false;
}

/// What the key [key] of a map of targets refers to: a type, an enum's
/// value.
Element? _keyElement(Expression key) => switch (key.unParenthesized) {
  TypeLiteral(:final type) => type.element,
  Identifier(:final element) => element,
  PropertyAccess(:final propertyName) => propertyName.element,
  _ => null,
};
