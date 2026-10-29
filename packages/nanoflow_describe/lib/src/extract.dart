// Reads the graphs of nodes of a package from its resolved sources, without
// running them (spec §7.1; graph node objects design §8–§9): every top-level
// variable made by `Graph(…)` is a graph, which describe.dart gives a graph
// file of its own.
//
// graphs.dart reads the parts of a graph and routes.dart its routes into the
// points of its body (_Points): its nodes, the forks of its routes and its
// joins, and the ways between them, which become the nodes and edges of the
// file.

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:nanoflow_model/nanoflow_model.dart';

part 'graphs.dart';
part 'routes.dart';

/// What [extract] read from the sources of a package.
typedef Extracted = ({
  /// The graphs, by id (`path#variable`), sorted by id.
  Map<String, GraphFunction> functions,

  /// The bodies of the routes of the graphs, whose side effects outside
  /// effects warn.
  List<FunctionBody> routes,

  /// What could not be drawn, each once.
  List<GraphWarning> warnings,

  /// The id of the graph of [functions] whose declaration — its `Graph(…)`
  /// — holds the line [line] of the file [path]; `null` when none does.
  String? Function(String path, int line) functionAt,
});

/// The graphs of the package whose sources are [units].
///
/// [paths] gives the path from the package root of every unit by its absolute
/// path.
Extracted extract(List<ResolvedUnitResult> units, Map<String, String> paths) =>
    _Package(units, paths)._extract();

/// The sources of a package: the nodes and graphs they declare, and where.
final class _Package {
  _Package(this._units, Map<String, String> paths)
    : _paths = {for (final unit in _units) unit.unit: paths[unit.path]!},
      _contents = {for (final unit in _units) unit.unit: unit.content},
      _libraryOf = {for (final unit in _units) unit.unit: unit.libraryElement};

  final List<ResolvedUnitResult> _units;

  /// The path from the package root of every unit.
  final Map<CompilationUnit, String> _paths;

  /// The text of every unit.
  final Map<CompilationUnit, String> _contents;

  /// The library of every unit, whose types its code uses.
  final Map<CompilationUnit, LibraryElement> _libraryOf;

  /// The body of every top-level function of the sources, by the function:
  /// a route may be one.
  final _functions = <Element, FunctionBody>{};

  /// The nodes and the graphs declared in top-level variables, by the
  /// variable.
  final _nodelikes = <Element, _Nodelike>{};

  /// The graphs among [_nodelikes].
  Iterable<_GraphDeclaration> get _graphs =>
      _nodelikes.values.whereType<_GraphDeclaration>();

  /// A set: a top-level function that is the route of two parts is read for
  /// each, and would repeat its warnings.
  final _warnings = <GraphWarning>{};

  Extracted _extract() {
    _index();
    for (final unit in _units) {
      _walk(unit.unit, _look);
    }
    final (functions, routes) = _drawGraphs();
    // A session is named after its graph, and a node's effect is found by
    // the name of its graph: a graph must not share its name.
    for (final graph in _graphs) {
      final twins = [
        for (final other in _graphs)
          if (other != graph && other.name == graph.name) other.id,
      ]..sort();
      if (twins.isNotEmpty) {
        _warn(
          graph.made,
          'graph name ${graph.name} is also the name of ${twins.join(', ')}',
        );
      }
    }
    // Where each graph is declared, by the first and last lines of its
    // `Graph(…)`.
    final spans = {for (final graph in _graphs) graph.id: _span(graph.made)};
    String? functionAt(String path, int line) {
      for (final MapEntry(key: id, value: (inPath, first, last))
          in spans.entries) {
        if (inPath == path && first <= line && line <= last) return id;
      }
      return null;
    }

    return (
      functions: {
        for (final id in functions.keys.toList()..sort()) id: functions[id]!,
      },
      routes: routes.toList(),
      warnings: _warnings.toList(),
      functionAt: functionAt,
    );
  }

  /// Finds every top-level function with a body, and every node and graph
  /// made in a top-level variable.
  void _index() {
    for (final unit in _units) {
      for (final declaration in unit.unit.declarations) {
        switch (declaration) {
          case FunctionDeclaration(
                :final declaredFragment?,
                :final functionExpression,
              )
              when !declaration.isGetter && !declaration.isSetter:
            final body = functionExpression.body;
            if (body is! EmptyFunctionBody && body is! NativeFunctionBody) {
              _functions[declaredFragment.element.baseElement] = body;
            }
          case TopLevelVariableDeclaration(
            :final variables,
            :final documentationComment,
          ):
            for (final variable in variables.variables) {
              _declareNodelike(variable, documentationComment);
            }
          default:
        }
      }
    }
  }

  /// Warns of [node] when it is a node or a graph made outside a top-level
  /// variable.
  void _look(AstNode node) {
    switch (node) {
      case final InstanceCreationExpression made
          when _makesGraph(made) && !_isDeclared(made):
        _warn(made, 'a graph outside a top-level variable is not drawn');
      case final MethodInvocation made
          when _makesNode(made) && !_isDeclared(made):
        _warn(made, 'a node outside a top-level variable is not drawn');
      default:
    }
  }

  // ---- sources, places and warnings -------------------------------------------

  /// The code of [node] as it is written, on one line (see [oneLine]).
  String _source(AstNode node) =>
      oneLine(_contents[node.root]!.substring(node.offset, node.end));

  /// `path:line` of [node], or of [offset] in its file.
  String _place(AstNode node, {int? offset}) {
    final unit = node.root as CompilationUnit;
    final line = unit.lineInfo.getLocation(offset ?? node.offset).lineNumber;
    return '${_paths[unit]}:$line';
  }

  /// The path of [node]'s file, and its first and last lines.
  (String, int, int) _span(AstNode node) {
    final unit = node.root as CompilationUnit;
    return (
      _paths[unit]!,
      unit.lineInfo.getLocation(node.offset).lineNumber,
      unit.lineInfo.getLocation(node.end).lineNumber,
    );
  }

  void _warn(AstNode node, String message) =>
      _warnings.add(GraphWarning(place: _place(node), message: message));
}

/// [code] on one line: a line break and the indents around it are one space,
/// none after an opening bracket or before a closing one, where a trailing
/// comma goes too (`a &&⏎    b` is `a && b`, `f(⏎  x,⏎)` is `f(x)`).
String oneLine(String code) => code
    .replaceAllMapped(RegExp(r'([(\[{])\s*\n\s*'), (m) => m[1]!)
    .replaceAllMapped(RegExp(r',?\s*\n\s*([)\]}])'), (m) => m[1]!)
    .replaceAll(RegExp(r'\s*\n\s*'), ' ');

/// The text of the doc comment whose tokens are [comments] (node docs
/// design §2): `///` lines without `///` and the space after it, a
/// `/** */` block without `/**`, `*/` and the `*` its lines start with;
/// blank lines at either end left out, Markdown as it is. `null` when
/// nothing is left.
String? docText(Iterable<Token> comments) {
  String unspaced(String line) =>
      line.startsWith(' ') ? line.substring(1) : line;
  final lines = <String>[];
  for (final comment in comments) {
    final text = comment.lexeme;
    if (text.startsWith('///')) {
      lines.add(unspaced(text.substring(3)));
    } else if (text.startsWith('/**') &&
        text.endsWith('*/') &&
        // `/**/` is empty, and its `*/` is the end of its `/**`.
        text.length >= 5) {
      for (final line in text.substring(3, text.length - 2).split('\n')) {
        final trimmed = line.trimLeft();
        lines.add(
          trimmed.startsWith('*') ? unspaced(trimmed.substring(1)) : trimmed,
        );
      }
    }
  }
  final trimmed = [for (final line in lines) line.trimRight()];
  final first = trimmed.indexWhere((line) => line.isNotEmpty);
  if (first == -1) return null;
  final last = trimmed.lastIndexWhere((line) => line.isNotEmpty);
  return trimmed.sublist(first, last + 1).join('\n');
}

/// Calls [visit] on [node] and every node below it.
void _walk(AstNode node, void Function(AstNode node) visit) {
  visit(node);
  for (final child in node.childEntities.whereType<AstNode>()) {
    _walk(child, visit);
  }
}

// ---- the points of a graph's body ---------------------------------------------

/// A point of a graph's body.
sealed class _V {}

/// Where the graph starts.
final class _Entry extends _V {}

/// Where the graph ends.
final class _Exit extends _V {}

/// Where the nodes of a join meet before its route. Not drawn.
final class _Join extends _V {}

/// A point drawn as a node, unless it is a fork that decides nothing.
sealed class _Drawn extends _V {
  _Drawn(this.place);
  final String place;

  GraphNode node(String id);
}

/// A node of the graph: an effect.
final class _Effect extends _Drawn {
  _Effect(this.name, super.place, this.doc);
  final String name;
  final String? doc;

  @override
  GraphNode node(String id) =>
      EffectNode(id: id, place: place, name: name, doc: doc);
}

/// A fork of a route.
final class _Fork extends _Drawn {
  _Fork(this.label, this.outcomes, super.place, {this.exitsOf});
  final String label;

  /// The labels of the ways out of the fork. One the flow cannot go on from
  /// (a `throw`) has no edge.
  final List<String> outcomes;

  /// The point whose own exits the fork's ways out are, drawn so when the
  /// fork is: no node, its ways out leave that point, labelled as they are
  /// (routes.dart).
  final _V? exitsOf;

  @override
  GraphNode node(String id) =>
      ConditionNode(id: id, place: place, label: label);
}

/// A graph that is a node of the graph: a call of it.
final class _Call extends _Drawn {
  _Call(this.functions, super.place);
  final List<String> functions;

  @override
  GraphNode node(String id) =>
      CallNode(id: id, place: place, functions: functions);
}

/// A way out of a point that does not lead anywhere yet, with the outcome
/// it is taken on when the point is a fork.
typedef _Out = (_V, String?);

/// The points of one graph's body and the ways between them; [_emit] gives
/// the body as the graph file has it.
final class _Points {
  _Points(this._package);

  final _Package _package;

  final _entry = _Entry();
  final _exit = _Exit();
  final _vertices = <_V>[];
  final _edges = <_V, List<(String?, _V)>>{};

  /// The fork of the switch [s], the labels of its members in order, and
  /// whether they match every value (an exhaustive switch or a `default`,
  /// `case _`): without, the fork has a `default` outcome of its own.
  (_Fork, List<String>, bool) _switchFork(SwitchStatement s) {
    final labels = [
      for (final member in s.members)
        switch (member) {
          SwitchDefault() => 'default',
          SwitchCase(:final expression) => _source(expression),
          SwitchPatternCase(:final guardedPattern) => _caseLabel(
            guardedPattern,
            _source,
          ),
        },
    ];
    final matchesAll =
        _isExhaustive(s.expression) ||
        s.members.any(
          (member) => switch (member) {
            SwitchDefault() => true,
            SwitchPatternCase(:final guardedPattern) => _matchesAll(
              guardedPattern,
            ),
            SwitchCase() => false,
          },
        );
    final fork = _fork('switch (${_source(s.expression)})', s.expression, [
      ...labels,
      if (!matchesAll) 'default',
    ]);
    return (fork, labels, matchesAll);
  }

  _Fork _fork(String label, AstNode at, List<String> outcomes, {_V? exitsOf}) =>
      _add(_Fork(label, outcomes, _package._place(at), exitsOf: exitsOf));

  _Join _join() => _add(_Join());

  T _add<T extends _V>(T v) {
    _vertices.add(v);
    return v;
  }

  /// Leads [from] to [to].
  void _connect(List<_Out> from, _V to) {
    for (final (v, outcome) in from) {
      (_edges[v] ??= []).add((outcome, to));
    }
  }

  // ---- the body in the graph file ---------------------------------------------

  /// The body as the graph file has it. [roots] are drawn, with where they
  /// lead, though no path from the entry reaches them: the nodes a graph
  /// declares.
  GraphBody _emit({Iterable<_V> roots = const []}) {
    // A fork whose outcomes all lead to the same nodes decides nothing that
    // can be seen: it is not drawn, as a join. An outcome without an edge
    // (a throw) leads nowhere, which differs from anywhere.
    // What no path from the entry or the roots reaches — the fork of a
    // switch whose cases are a node's exits — is not drawn either.
    final reached = <_V>{};
    for (final queue = <_V>[_entry, ...roots]; queue.isNotEmpty;) {
      final v = queue.removeLast();
      if (!reached.add(v)) continue;
      for (final (_, to) in _edges[v] ?? const <(String?, _V)>[]) {
        queue.add(to);
      }
    }
    final hidden = <_V>{
      ..._vertices.whereType<_Join>(),
      ..._vertices.where((v) => !reached.contains(v)),
    };
    for (var changed = true; changed;) {
      changed = false;
      for (final fork in _vertices.whereType<_Fork>()) {
        if (hidden.contains(fork)) continue;
        final outcomes = <String?, Set<_V>>{
          for (final outcome in fork.outcomes) outcome: {},
        };
        for (final (outcome, to) in _edges[fork] ?? const <(String?, _V)>[]) {
          (outcomes[outcome] ??= {}).addAll(_resolve({to}, hidden));
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
    // Node ids: decimal, in the order the nodes were made. A fork that is
    // the exits of a point is no node.
    final ids = <_Drawn, String>{};
    for (final v in _vertices.whereType<_Drawn>()) {
      if (!hidden.contains(v) && !(v is _Fork && v.exitsOf != null)) {
        ids[v] = '${ids.length + 1}';
      }
    }
    final edges = <GraphEdge>[];
    final seen = <(String?, String?, String?)>{};
    void edgesOf(_V from, String? fromId) {
      for (final (label, to) in _edges[from] ?? const <(String?, _V)>[]) {
        if (to is _Fork &&
            identical(to.exitsOf, from) &&
            !hidden.contains(to)) {
          edgesOf(to, fromId);
          continue;
        }
        for (final target in _resolve({to}, hidden)) {
          final toId = ids[target];
          if (seen.add((fromId, toId, label))) {
            edges.add(GraphEdge(from: fromId, to: toId, label: label));
          }
        }
      }
    }

    edgesOf(_entry, null);
    for (final MapEntry(key: v, value: id) in ids.entries) {
      edgesOf(v, id);
    }
    return GraphBody(
      nodes: [
        for (final MapEntry(key: v, value: id) in ids.entries) v.node(id),
      ],
      edges: edges,
    );
  }

  /// The points [vs] lead to that are drawn, or the exit, through hidden
  /// ones.
  Set<_V> _resolve(Set<_V> vs, Set<_V> hidden, [Set<_V>? seen]) {
    seen ??= {};
    final result = <_V>{};
    for (final v in vs) {
      if (!hidden.contains(v)) {
        result.add(v);
      } else if (seen.add(v)) {
        result.addAll(
          _resolve(
            {for (final (_, to) in _edges[v] ?? const <(String?, _V)>[]) to},
            hidden,
            seen,
          ),
        );
      }
    }
    return result;
  }

  String _source(AstNode node) => _package._source(node);

  String _loopVariable(ForEachParts parts) => switch (parts) {
    ForEachPartsWithDeclaration(:final loopVariable) =>
      loopVariable.name.lexeme,
    ForEachPartsWithIdentifier(:final identifier) => identifier.name,
    ForEachPartsWithPattern(:final pattern) => _source(pattern),
  };
}

/// The label of a case of a switch: its pattern by what it matches, not
/// what it binds — an object pattern by its type and the fields it tests,
/// `Passed` for `Passed(:final verdict)` and `Draft(text: '')` as it is, a
/// variable pattern by its type — and its `when` clause as written.
String _caseLabel(GuardedPattern guarded, String Function(AstNode) source) {
  /// Whether [pattern] only binds, testing nothing: `final x`, `var x`, `_`.
  bool binds(DartPattern pattern) => switch (pattern) {
    WildcardPattern(type: null) => true,
    DeclaredVariablePattern(type: null) => true,
    _ => false,
  };
  String matched(DartPattern pattern) => switch (pattern) {
    ObjectPattern(:final type, :final fields) => switch ([
      for (final field in fields)
        if (!binds(field.pattern)) source(field),
    ]) {
      [] => source(type),
      final tested => '${source(type)}(${tested.join(', ')})',
    },
    DeclaredVariablePattern(:final type?) => source(type),
    ParenthesizedPattern(:final pattern) => matched(pattern),
    LogicalOrPattern(:final leftOperand, :final rightOperand) =>
      '${matched(leftOperand)} || ${matched(rightOperand)}',
    _ => source(pattern),
  };
  final label = matched(guarded.pattern);
  return switch (guarded.whenClause) {
    final clause? => '$label ${source(clause)}',
    null => label,
  };
}

/// Whether a case matches every value: `_` or `var x`, untyped, unguarded.
bool _matchesAll(GuardedPattern pattern) =>
    pattern.whenClause == null &&
    switch (pattern.pattern) {
      WildcardPattern(type: null) ||
      DeclaredVariablePattern(type: null) => true,
      _ => false,
    };

/// Whether a switch on [e] matches every value without a `default`: Dart
/// requires it for `bool`, enums, sealed types and records of them.
bool _isExhaustive(Expression e) => _mustBeCovered(e.staticType);

/// Whether a switch on a value of [type] must cover every value: [type] is
/// `bool`, an enum, a sealed type, or a record whose fields all are.
bool _mustBeCovered(DartType? type) {
  if (type is RecordType) {
    return [
      for (final field in type.positionalFields) field.type,
      for (final field in type.namedFields) field.type,
    ].every(_mustBeCovered);
  }
  final element = type?.element;
  return element is EnumElement ||
      (element is ClassElement && element.isSealed) ||
      type?.isDartCoreBool == true;
}

/// The first positional argument in [arguments], or `null`: a named one may
/// come before it, as in `flow.start(id: id, review, branch)`.
Expression? _firstPositional(ArgumentList arguments) => arguments.arguments
    .where((argument) => argument is! NamedArgument)
    .firstOrNull
    ?.argumentExpression;
