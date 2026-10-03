// Reads the functions with steps of a package from its resolved sources,
// without running them: every step a function can take and every way between
// them (spec §7.1). Ported from prototypes/static_graph, which inlined the
// functions it called; here a call is a node, and the function it calls has a
// graph of its own.
//
// A body is followed statement by statement; what is left of its control flow
// between `Flow.step` calls, calls of functions with steps and copies run by
// `Future.wait` are the edges. An `if`, a loop and a `switch` are forks,
// labelled with their source.

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:nanoflow_model/nanoflow_model.dart';

/// What [extract] read from the sources of a package.
typedef Extracted = ({
  /// The ids of the functions passed first to `Flow.start`, `Flow.run` or
  /// `Flow.resume`, sorted.
  List<String> workflows,

  /// The functions with steps and the workflows by id, sorted by id.
  Map<String, GraphFunction> functions,

  /// What could not be drawn, sorted by place.
  List<GraphWarning> warnings,
});

/// The functions with steps of the package whose sources are [units].
///
/// [paths] gives the path from the package root of every unit by its absolute
/// path. [session] resolved [units]; a function outside them that a source
/// calls with a `Flow` is read through it to tell whether it has steps.
Future<Extracted> extract(
  List<ResolvedUnitResult> units,
  Map<String, String> paths,
  AnalysisSession session,
) async {
  final package = _Package(units, paths);
  await package._findStepsOutside(session);
  return package._extract();
}

/// A function or method of the sources that has a body.
final class _Declaration {
  _Declaration(this.id, this.name, this.place, this.body);

  /// `path#name`, and `path#Class.name` for a method.
  final String id;
  final String name;
  final String place;
  final FunctionBody body;
}

/// The sources of a package: what they declare and call, and where.
final class _Package {
  _Package(this._units, Map<String, String> paths)
    : _paths = {for (final unit in _units) unit.unit: paths[unit.path]!},
      _contents = {for (final unit in _units) unit.unit: unit.content},
      _libraries = {for (final unit in _units) unit.libraryElement};

  final List<ResolvedUnitResult> _units;

  /// The path from the package root of every unit.
  final Map<CompilationUnit, String> _paths;

  /// The text of every unit.
  final Map<CompilationUnit, String> _contents;
  final Set<LibraryElement> _libraries;

  final _declarations = <ExecutableElement, _Declaration>{};

  /// The methods of the sources that override a method, by the method.
  final _overriders = <ExecutableElement, Set<_Declaration>>{};

  /// The functions with steps, once [_findWithSteps] has found them.
  final _withSteps = <_Declaration>{};

  /// The functions outside the sources that take steps.
  final _stepsOutside = <ExecutableElement>{};

  final _stepsMemo = <AstNode, bool>{};
  final _warnings = <GraphWarning>[];

  /// Reads the functions outside the sources that the sources call with a
  /// `Flow`, to warn that their steps are not drawn.
  Future<void> _findStepsOutside(AnalysisSession session) async {
    final callees = <ExecutableElement>{};
    for (final unit in _units) {
      _walk(unit.unit, (node) {
        final callee = _callee(node)?.element;
        if (callee != null && _isOutside(callee) && _takesFlow(callee)) {
          callees.add(callee);
        }
      });
    }
    final libraries = <LibraryElement, ResolvedLibraryResult?>{};
    for (final callee in callees) {
      final library = libraries.containsKey(callee.library)
          ? libraries[callee.library]
          : libraries[callee.library] = switch (await session
                .getResolvedLibraryByElement(callee.library)) {
              final ResolvedLibraryResult result => result,
              _ => null,
            };
      final body = switch (library
          ?.getFragmentDeclaration(callee.firstFragment)
          ?.node) {
        FunctionDeclaration(:final functionExpression) =>
          functionExpression.body,
        MethodDeclaration(:final body) => body,
        _ => null,
      };
      if (body != null && _takesStepItself(body)) _stepsOutside.add(callee);
    }
  }

  Extracted _extract() {
    _index();
    _findWithSteps();
    final workflows = <_Declaration>{};
    for (final unit in _units) {
      _walk(unit.unit, (node) => _look(node, workflows));
    }
    final drawn = {..._withSteps, ...workflows}.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final functions = {
      for (final d in drawn)
        d.id: GraphFunction(
          id: d.id,
          name: d.name,
          place: d.place,
          body: _Body(this).ofFunction(d.body),
        ),
    };
    return (
      workflows: [for (final d in workflows) d.id]..sort(),
      functions: functions,
      warnings: _warnings..sort(_byPlace),
    );
  }

  // ---- what the sources declare ---------------------------------------------

  /// Finds every function and method with a body, and what overrides what.
  void _index() {
    for (final unit in _units) {
      _walk(unit.unit, (node) {
        switch (node) {
          case final FunctionDeclaration function
              when function.parent is CompilationUnit &&
                  !function.isGetter &&
                  !function.isSetter:
            if (function.declaredFragment case final fragment?) {
              _declare(
                fragment.element,
                function.name,
                function.functionExpression.body,
              );
            }
          case final MethodDeclaration method
              when !method.isGetter && !method.isSetter && !method.isOperator:
            if (method.declaredFragment case final fragment?) {
              _declare(fragment.element, method.name, method.body);
            }
          default:
        }
      });
    }
    for (final MapEntry(key: element, value: method) in _declarations.entries) {
      if (element.enclosingElement case final InterfaceElement type) {
        for (final supertype in type.allSupertypes) {
          if (supertype.getMethod(element.name!) case final overridden?) {
            (_overriders[overridden.baseElement] ??= {}).add(method);
          }
        }
      }
    }
  }

  void _declare(ExecutableElement element, Token name, FunctionBody body) {
    if (body is EmptyFunctionBody || body is NativeFunctionBody) return;
    final container = switch (element.enclosingElement) {
      final InstanceElement type => '${type.name ?? ''}.',
      _ => '',
    };
    _declarations[element.baseElement] = _Declaration(
      '${_paths[body.root]}#$container${name.lexeme}',
      name.lexeme,
      _place(body, offset: name.offset),
      body,
    );
  }

  /// Finds the functions with steps: those that take a step and, until
  /// nothing changes, those that call one of them.
  void _findWithSteps() {
    final callees = <_Declaration, Set<_Declaration>>{};
    for (final declaration in _declarations.values) {
      var steps = false;
      final calls = callees[declaration] = {};
      _walkRunning(declaration.body, (node) {
        if (node is MethodInvocation && _isStep(node)) steps = true;
        calls.addAll(_candidates(node));
      });
      if (steps) _withSteps.add(declaration);
    }
    for (var changed = true; changed;) {
      changed = false;
      for (final MapEntry(key: declaration, value: calls) in callees.entries) {
        if (!_withSteps.contains(declaration) &&
            calls.any(_withSteps.contains)) {
          _withSteps.add(declaration);
          changed = true;
        }
      }
    }
  }

  /// Takes the workflows and the warnings of the whole sources from [node],
  /// in a function with steps or not.
  void _look(AstNode node, Set<_Declaration> workflows) {
    switch (node) {
      case final FunctionExpression closure
          when closure.parent is! FunctionDeclaration &&
              !_runsHere(closure) &&
              _hasSteps(closure.body):
        _warn(closure, 'steps in a closure passed on are not drawn');
      case final FunctionDeclaration local
          when local.parent is FunctionDeclarationStatement &&
              _hasSteps(local.functionExpression.body):
        _warn(
          local,
          'steps in a local function are not drawn',
          offset: local.name.offset,
        );
      case final MethodInvocation start
          when _isFlow(start, const {'start', 'run', 'resume'}):
        final workflow = _referenced(
          start.argumentList.arguments.firstOrNull?.argumentExpression,
        );
        if (_declarations[workflow?.baseElement] case final declaration?) {
          workflows.add(declaration);
        }
      default:
    }
    if (_callee(node)?.element case final callee?
        when _stepsOutside.contains(callee)) {
      _warn(
        node,
        'steps of ${callee.name} are not drawn: '
        'it is outside the package sources',
      );
    }
  }

  // ---- steps and calls --------------------------------------------------------

  /// Whether running [node] can take a step: a closure written in it does
  /// not run there, a function with steps it calls does.
  bool _hasSteps(AstNode node) => _stepsMemo[node] ??= _findsSteps(node);

  bool _findsSteps(AstNode node) {
    if (node is FunctionExpression && !_runsHere(node)) return false;
    if (node is MethodInvocation && _isStep(node)) return true;
    if (_callTargets(node).isNotEmpty) return true;
    return node.childEntities.whereType<AstNode>().any(_hasSteps);
  }

  /// The ids of the functions with steps that [node] calls, sorted: one for a
  /// function, every implementation for a method of an interface.
  List<String> _callTargets(AstNode node) => [
    for (final d in _candidates(node))
      if (_withSteps.contains(d)) d.id,
  ]..sort();

  /// The functions of the sources that [node] can call.
  Set<_Declaration> _candidates(AstNode node) {
    final callee = _callee(node);
    if (callee == null) return const {};
    return {
      ?_declarations[callee.element],
      if (callee.virtual) ...?_overriders[callee.element],
    };
  }

  /// The function [node] calls, if it is a call; `virtual` when the call can
  /// go to a method that overrides it.
  ({ExecutableElement element, bool virtual})? _callee(AstNode node) {
    final (element, virtual) = switch (node) {
      MethodInvocation(:final methodName, :final target) => (
        methodName.element,
        target is! SuperExpression,
      ),
      FunctionExpressionInvocation(:final element) => (element, false),
      _ => (null, false),
    };
    if (element is! ExecutableElement) return null;
    final base = element.baseElement;
    return (
      element: base,
      virtual: virtual && base is MethodElement && !base.isStatic,
    );
  }

  /// Calls [visit] on [node] and every node below it that runs with it: not
  /// in a closure passed on.
  void _walkRunning(AstNode node, void Function(AstNode node) visit) {
    if (node is FunctionExpression && !_runsHere(node)) return;
    visit(node);
    for (final child in node.childEntities.whereType<AstNode>()) {
      _walkRunning(child, visit);
    }
  }

  bool _isOutside(ExecutableElement element) =>
      !_libraries.contains(element.library) &&
      !element.library.uri.toString().startsWith('package:nanoflow/');

  bool _takesFlow(ExecutableElement element) =>
      element.formalParameters.any((parameter) => _isFlowType(parameter.type));

  /// Whether [body] calls `Flow.step` where it runs.
  bool _takesStepItself(FunctionBody body) {
    var steps = false;
    _walkRunning(body, (node) {
      if (node is MethodInvocation && _isStep(node)) steps = true;
    });
    return steps;
  }

  bool _isStep(MethodInvocation node) => _isFlow(node, const {'step'});

  /// Whether [node] calls a method of `Flow` named one of [names].
  bool _isFlow(MethodInvocation node, Set<String> names) {
    final method = node.methodName.element;
    return method is MethodElement &&
        names.contains(method.name) &&
        _isFlowClass(method.enclosingElement);
  }

  bool _isFlowType(DartType type) => _isFlowClass(type.element);

  bool _isFlowClass(Element? element) =>
      element is ClassElement &&
      element.name == 'Flow' &&
      element.library.uri.toString().startsWith('package:nanoflow/');

  bool _isFutureWait(AstNode node) {
    if (node is! MethodInvocation) return false;
    final method = node.methodName.element;
    return method is MethodElement &&
        method.name == 'wait' &&
        method.enclosingElement?.name == 'Future' &&
        method.library.uri.toString() == 'dart:async';
  }

  /// Whether [node] is `(a, b).wait` of `dart:async`, which runs the futures
  /// of a record side by side.
  bool _isRecordWait(PropertyAccess node) {
    final getter = node.propertyName.element;
    return getter != null &&
        getter.name == 'wait' &&
        getter.enclosingElement is ExtensionElement &&
        getter.library?.uri.toString() == 'dart:async';
  }

  /// Whether [closure] runs where it is written: called in place, or given
  /// to the `map` whose copies `Future.wait` runs.
  bool _runsHere(FunctionExpression closure) {
    final parent = _outermost(closure).parent;
    if (parent is FunctionExpressionInvocation) {
      return parent.function.unParenthesized == closure;
    }
    if (parent
        case ArgumentList(parent: final MethodInvocation map, arguments: [_])
        when map.methodName.name == 'map' && map.target != null) {
      return _isWaited(map);
    }
    return false;
  }

  /// Whether [futures] is the first argument of `Future.wait`.
  bool _isWaited(Expression futures) {
    final node = _outermost(futures);
    final parent = node.parent;
    return parent is ArgumentList &&
        parent.arguments.firstOrNull == node &&
        _isFutureWait(parent.parent!);
  }

  /// [node] with the parentheses around it.
  AstNode _outermost(AstNode node) {
    var outer = node;
    while (outer.parent is ParenthesizedExpression) {
      outer = outer.parent!;
    }
    return outer;
  }

  /// The function or method [expression] refers to, like `review` in
  /// `flow.run(review, …)`.
  ExecutableElement? _referenced(Expression? expression) {
    final element = switch (expression?.unParenthesized) {
      Identifier(:final element) => element,
      PropertyAccess(:final propertyName) => propertyName.element,
      FunctionReference(:final function) => _referenced(function),
      _ => null,
    };
    return element is ExecutableElement ? element : null;
  }

  // ---- sources, places and warnings -------------------------------------------

  /// The code of [node] as it is written, on one line: a line break and the
  /// indents around it are one space, none after an opening bracket or
  /// before a closing one, where a trailing comma goes too (`a &&⏎    b` is
  /// `a && b`, `f(⏎  x,⏎)` is `f(x)`).
  String _source(AstNode node) => _contents[node.root]!
      .substring(node.offset, node.end)
      .replaceAllMapped(RegExp(r'([(\[{])\s*\n\s*'), (m) => m[1]!)
      .replaceAllMapped(RegExp(r',?\s*\n\s*([)\]}])'), (m) => m[1]!)
      .replaceAll(RegExp(r'\s*\n\s*'), ' ');

  /// `path:line` of [node], or of [offset] in its file.
  String _place(AstNode node, {int? offset}) {
    final unit = node.root as CompilationUnit;
    final line = unit.lineInfo.getLocation(offset ?? node.offset).lineNumber;
    return '${_paths[unit]}:$line';
  }

  void _warn(AstNode node, String message, {int? offset}) => _warnings.add(
    GraphWarning(
      place: _place(node, offset: offset),
      message: message,
    ),
  );

  /// By path, then by line, then by message.
  static int _byPlace(GraphWarning a, GraphWarning b) {
    final (pathA, lineA) = _split(a.place!);
    final (pathB, lineB) = _split(b.place!);
    final byPath = pathA.compareTo(pathB);
    if (byPath != 0) return byPath;
    final byLine = lineA.compareTo(lineB);
    return byLine != 0 ? byLine : a.message.compareTo(b.message);
  }

  static (String, int) _split(String place) {
    final colon = place.lastIndexOf(':');
    return (place.substring(0, colon), int.parse(place.substring(colon + 1)));
  }
}

/// Calls [visit] on [node] and every node below it.
void _walk(AstNode node, void Function(AstNode node) visit) {
  visit(node);
  for (final child in node.childEntities.whereType<AstNode>()) {
    _walk(child, visit);
  }
}

// ---- the graph of one body ----------------------------------------------------

/// A point of the control flow.
sealed class _V {}

/// Where the body is entered.
final class _Entry extends _V {}

/// Where the body is left: a `return` or its end.
final class _Exit extends _V {}

/// Where ways meet: a loop's head, the end of a `do` body. Not drawn.
final class _Join extends _V {}

/// A point drawn as a node, unless it is a fork that decides nothing.
sealed class _Drawn extends _V {
  _Drawn(this.place);
  final String place;

  GraphNode node(String id);
}

final class _Step extends _Drawn {
  _Step(this.name, super.place);
  final String name;

  @override
  GraphNode node(String id) => StepNode(id: id, place: place, name: name);
}

final class _Fork extends _Drawn {
  _Fork(this.label, this.outcomes, super.place);
  final String label;

  /// The labels of the ways out of the fork. One the flow cannot go on from
  /// (a `throw`) has no edge.
  final List<String> outcomes;

  @override
  GraphNode node(String id) =>
      ConditionNode(id: id, place: place, label: label);
}

final class _Call extends _Drawn {
  _Call(this.functions, super.place);
  final List<String> functions;

  @override
  GraphNode node(String id) =>
      CallNode(id: id, place: place, functions: functions);
}

final class _Copies extends _Drawn {
  _Copies(this.label, this.body, super.place);
  final String label;
  final GraphBody body;

  @override
  GraphNode node(String id) =>
      CopiesNode(id: id, place: place, label: label, body: body);
}

/// A way out of a point that does not lead anywhere yet, with the outcome
/// it is taken on when the point is a fork.
typedef _Out = (_V, String?);

/// Where `return`, `break` and `continue` lead from the current statement.
final class _Scope {
  const _Scope({
    this.returns,
    this.breaks = const {},
    this.continues = const {},
  });

  /// Ways out of a `return`; `null` in the body itself, where a `return`
  /// leaves the body.
  final List<_Out>? returns;

  /// Ways out of a `break` by the statement it leaves.
  final Map<AstNode, List<_Out>> breaks;

  /// Where a `continue` goes by the loop it continues.
  final Map<AstNode, _V> continues;

  _Scope loop(AstNode loop, List<_Out> breaks, _V continues) => _Scope(
    returns: returns,
    breaks: {...this.breaks, loop: breaks},
    continues: {...this.continues, loop: continues},
  );

  _Scope breaking(AstNode statement, List<_Out> breaks) => _Scope(
    returns: returns,
    breaks: {...this.breaks, statement: breaks},
    continues: continues,
  );
}

/// The graph of one body: a function's or a copy's.
final class _Body {
  _Body(this._package);

  final _Package _package;

  final _entry = _Entry();
  final _exit = _Exit();
  final _vertices = <_V>[];
  final _edges = <_V, List<(String?, _V)>>{};

  GraphBody ofFunction(FunctionBody body) {
    _connect(_body(body, [(_entry, null)], const _Scope()), _exit);
    return _emit();
  }

  /// The graph of one copy whose body is [body]: a closure or an
  /// expression.
  GraphBody ofCopy(AstNode body) {
    final exits = body is FunctionExpression
        ? _body(body.body, [(_entry, null)], const _Scope())
        : _expression(body, [(_entry, null)], const _Scope());
    _connect(exits, _exit);
    return _emit();
  }

  // ---- statements -------------------------------------------------------------

  List<_Out> _body(FunctionBody body, List<_Out> into, _Scope scope) =>
      switch (body) {
        BlockFunctionBody(:final block) => _statement(block, into, scope),
        ExpressionFunctionBody(:final expression) => _expression(
          expression,
          into,
          scope,
        ),
        _ => into,
      };

  List<_Out> _statements(
    Iterable<Statement> statements,
    List<_Out> into,
    _Scope scope,
  ) {
    var current = into;
    for (final statement in statements) {
      current = _statement(statement, current, scope);
    }
    return current;
  }

  List<_Out> _statement(Statement s, List<_Out> into, _Scope scope) {
    if (into.isEmpty) return into; // unreachable
    // No step and no jump out of it: the flow goes through as if it were not
    // there.
    if (!_package._hasSteps(s) && !_jumpsOut(s)) return into;
    switch (s) {
      case Block():
        return _statements(s.statements, into, scope);
      case ReturnStatement():
        _return(switch (s.expression) {
          final e? => _expression(e, into, scope),
          null => into,
        }, scope);
        return const [];
      case ExpressionStatement(
        expression: final Expression e &&
            (ThrowExpression() || RethrowExpression()),
      ):
        // The flow ends here, as a failure: no edge leaves.
        _children(e, into, scope);
        return const [];
      case IfStatement():
        final condition = _expression(s.expression, into, scope);
        final label = switch (s.caseClause) {
          final c? => '${_source(s.expression)} ${_source(c)}',
          null => _source(s.expression),
        };
        final fork = _fork(label, s.expression, _ifOutcomes);
        _connect(condition, fork);
        return [
          ..._statement(s.thenStatement, [(fork, 'true')], scope),
          ...switch (s.elseStatement) {
            final e? => _statement(e, [(fork, 'false')], scope),
            null => [(fork, 'false')],
          },
        ];
      case WhileStatement():
        final head = _join();
        _connect(into, head);
        final condition = _expression(s.condition, [(head, null)], scope);
        final breaks = <_Out>[];
        final inner = scope.loop(s, breaks, head);
        if (_isTrue(s.condition)) {
          _connect(_statement(s.body, condition, inner), head);
          return breaks;
        }
        final fork = _fork(
          'while (${_source(s.condition)})',
          s.condition,
          _ifOutcomes,
        );
        _connect(condition, fork);
        _connect(_statement(s.body, [(fork, 'true')], inner), head);
        return [(fork, 'false'), ...breaks];
      case DoStatement():
        final head = _join();
        final next = _join();
        _connect(into, head);
        final breaks = <_Out>[];
        _connect(
          _statement(s.body, [(head, null)], scope.loop(s, breaks, next)),
          next,
        );
        final condition = _expression(s.condition, [(next, null)], scope);
        if (_isTrue(s.condition)) {
          _connect(condition, head);
          return breaks;
        }
        final fork = _fork(
          'while (${_source(s.condition)})',
          s.condition,
          _ifOutcomes,
        );
        _connect(condition, fork);
        _connect([(fork, 'true')], head);
        return [(fork, 'false'), ...breaks];
      case ForStatement():
        return _for(s, into, scope);
      case SwitchStatement():
        return _switch(s, into, scope);
      case BreakStatement(:final target?):
        scope.breaks[target]?.addAll(into);
        return const [];
      case ContinueStatement(:final target?):
        if (scope.continues[target] case final next?) _connect(into, next);
        return const [];
      case LabeledStatement():
        final breaks = <_Out>[];
        final exits = _statement(
          s.unlabeled,
          into,
          scope.breaking(s.unlabeled, breaks),
        );
        return [...exits, ...breaks];
      case TryStatement():
        return _try(s, into, scope);
      default:
        return _children(s, into, scope);
    }
  }

  /// Leaves the body, or the closure called in place, from [exits].
  void _return(List<_Out> exits, _Scope scope) {
    if (scope.returns case final returns?) {
      returns.addAll(exits);
    } else {
      _connect(exits, _exit);
    }
  }

  /// The body, then `finally`: every way out of the body, a `return`, a
  /// `break` or a `continue` too, goes through `finally` before it goes on.
  /// `finally` is drawn once for each way out the body takes.
  List<_Out> _try(TryStatement s, List<_Out> into, _Scope scope) {
    if (s.catchClauses.isNotEmpty &&
        (_package._hasSteps(s.body) ||
            s.catchClauses.any((c) => _package._hasSteps(c.body)))) {
      _package._warn(s.catchClauses.first, 'catch clauses are not drawn');
    }
    final finallyBlock = s.finallyBlock;
    if (finallyBlock == null) return _statement(s.body, into, scope);
    // The jumps out of the body stop here first.
    final jumps = _Scope(
      returns: [],
      breaks: {for (final target in scope.breaks.keys) target: []},
      continues: {for (final target in scope.continues.keys) target: _join()},
    );
    final exits = _statement(s.body, into, jumps);
    final after = _statement(finallyBlock, exits, scope);
    if (jumps.returns!.isNotEmpty) {
      _return(_statement(finallyBlock, jumps.returns!, scope), scope);
    }
    for (final MapEntry(key: target, value: breaks) in jumps.breaks.entries) {
      if (breaks.isNotEmpty) {
        scope.breaks[target]!.addAll(_statement(finallyBlock, breaks, scope));
      }
    }
    for (final MapEntry(key: target, value: next) in jumps.continues.entries) {
      if (_isEntered(next)) {
        _connect(
          _statement(finallyBlock, [(next, null)], scope),
          scope.continues[target]!,
        );
      }
    }
    return after;
  }

  List<_Out> _for(ForStatement s, List<_Out> into, _Scope scope) {
    final breaks = <_Out>[];
    switch (s.forLoopParts) {
      case final ForEachParts parts:
        final items = _expression(parts.iterable, into, scope);
        final head = _join();
        _connect(items, head);
        final fork = _fork(
          'for ${_loopVariable(parts)} in ${_source(parts.iterable)}',
          parts.iterable,
          const ['each', 'done'],
        );
        _connect([(head, null)], fork);
        _connect(
          _statement(s.body, [(fork, 'each')], scope.loop(s, breaks, head)),
          head,
        );
        return [(fork, 'done'), ...breaks];
      case final ForParts parts:
        final current = switch (parts) {
          ForPartsWithDeclarations(:final variables) => _expression(
            variables,
            into,
            scope,
          ),
          ForPartsWithExpression(:final initialization?) => _expression(
            initialization,
            into,
            scope,
          ),
          ForPartsWithPattern(:final variables) => _expression(
            variables,
            into,
            scope,
          ),
          _ => into,
        };
        final head = _join();
        final next = _join();
        _connect(current, head);
        final List<_Out> bodyEntry;
        final List<_Out> out;
        if (parts.condition case final c?) {
          final condition = _expression(c, [(head, null)], scope);
          final fork = _fork('for (; ${_source(c)};)', c, _ifOutcomes);
          _connect(condition, fork);
          bodyEntry = [(fork, 'true')];
          out = [(fork, 'false')];
        } else {
          bodyEntry = [(head, null)];
          out = const [];
        }
        _connect(
          _statement(s.body, bodyEntry, scope.loop(s, breaks, next)),
          next,
        );
        var updated = <_Out>[(next, null)];
        for (final updater in parts.updaters) {
          updated = _expression(updater, updated, scope);
        }
        _connect(updated, head);
        return [...out, ...breaks];
    }
  }

  List<_Out> _switch(SwitchStatement s, List<_Out> into, _Scope scope) {
    final labels = [
      for (final member in s.members)
        switch (member) {
          SwitchDefault() => 'default',
          SwitchCase(:final expression) => _source(expression),
          SwitchPatternCase(:final guardedPattern) => _source(guardedPattern),
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
    final value = _expression(s.expression, into, scope);
    final fork = _fork('switch (${_source(s.expression)})', s.expression, [
      ...labels,
      if (!matchesAll) 'default',
    ]);
    _connect(value, fork);
    final breaks = <_Out>[];
    final inner = scope.breaking(s, breaks);
    final exits = <_Out>[];
    // Cases with no statements of their own share the body of the next one.
    final pending = <String>[];
    for (final (i, member) in s.members.indexed) {
      pending.add(labels[i]);
      if (member.statements.isEmpty) continue;
      exits.addAll(
        _statements(member.statements, [
          for (final label in pending) (fork, label),
        ], inner),
      );
      pending.clear();
    }
    exits.addAll([for (final label in pending) (fork, label)]);
    if (!matchesAll) exits.add((fork, 'default'));
    return [...exits, ...breaks];
  }

  /// Whether [s] has a `return`, a `throw`, or a `break` or `continue` that
  /// leaves it.
  bool _jumpsOut(Statement s) {
    var jumps = false;
    void visit(AstNode node) {
      if (jumps) return;
      switch (node) {
        case FunctionExpression():
          return; // a return in it leaves the closure
        case ReturnStatement() ||
            ExpressionStatement(
              expression: ThrowExpression() || RethrowExpression(),
            ):
          jumps = true;
        case BreakStatement(:final target) || ContinueStatement(:final target):
          jumps = target == null || !_isWithin(target, s);
        default:
          node.childEntities.whereType<AstNode>().forEach(visit);
      }
    }

    visit(s);
    return jumps;
  }

  // ---- expressions ------------------------------------------------------------

  List<_Out> _expression(AstNode e, List<_Out> into, _Scope scope) {
    // A closure's body does not run where the closure is written, unless it
    // is called right there; that call draws it.
    if (into.isEmpty || !_package._hasSteps(e)) return into;
    switch (e) {
      case MethodInvocation() when _package._isStep(e):
        final step = _step(e);
        _connect(into, step);
        return [(step, null)];
      case MethodInvocation() when _package._isFutureWait(e):
        final futures = e.argumentList.arguments.first.argumentExpression;
        return _parallel(futures, into, scope);
      case FunctionExpressionInvocation(:final function)
          when function.unParenthesized is FunctionExpression:
        // A closure called in place: its body runs here.
        final closure = function.unParenthesized as FunctionExpression;
        final arguments = _expression(e.argumentList, into, scope);
        final returns = <_Out>[];
        final exits = _body(closure.body, arguments, _Scope(returns: returns));
        return [...exits, ...returns];
      case PropertyAccess(target: RecordLiteral(:final fields))
          when _package._isRecordWait(e):
        // `(a, b).wait`: each field starts here, side by side.
        return [
          for (final field in fields)
            if (_package._hasSteps(field)) ..._expression(field, into, scope),
        ];
      case ConditionalExpression():
        final condition = _expression(e.condition, into, scope);
        final fork = _fork(_source(e.condition), e.condition, _ifOutcomes);
        _connect(condition, fork);
        return [
          ..._expression(e.thenExpression, [(fork, 'true')], scope),
          ..._expression(e.elseExpression, [(fork, 'false')], scope),
        ];
      case SwitchExpression(:final cases):
        // Exhaustive by the language: no default.
        final value = _expression(e.expression, into, scope);
        final labels = [for (final c in cases) _source(c.guardedPattern)];
        final fork = _fork(
          'switch (${_source(e.expression)})',
          e.expression,
          labels,
        );
        _connect(value, fork);
        return [
          for (final (i, c) in cases.indexed)
            ..._expression(c.expression, [(fork, labels[i])], scope),
        ];
      case BinaryExpression(:final operator)
          when (operator.type == TokenType.AMPERSAND_AMPERSAND ||
                  operator.type == TokenType.BAR_BAR) &&
              _package._hasSteps(e.rightOperand):
        final left = _expression(e.leftOperand, into, scope);
        final fork = _fork(_source(e.leftOperand), e.leftOperand, _ifOutcomes);
        _connect(left, fork);
        final (
          evaluates,
          skips,
        ) = operator.type == TokenType.AMPERSAND_AMPERSAND
            ? ('true', 'false')
            : ('false', 'true');
        return [
          ..._expression(e.rightOperand, [(fork, evaluates)], scope),
          (fork, skips),
        ];
      default:
        final current = _children(e, into, scope);
        final functions = _package._callTargets(e);
        if (functions.isEmpty) return current;
        final call = _add(
          _Call(
            functions,
            _package._place(
              e,
              offset: e is MethodInvocation ? e.methodName.offset : null,
            ),
          ),
        );
        _connect(current, call);
        return [(call, null)];
    }
  }

  /// What `Future.wait` over [futures] runs: each element of a list starts
  /// here, a `for` element or a `map` runs copies of its body; the flow goes
  /// on when all are done.
  List<_Out> _parallel(Expression futures, List<_Out> into, _Scope scope) {
    switch (futures) {
      case ListLiteral(:final elements):
        final exits = <_Out>[];
        for (final element in elements) {
          if (!_package._hasSteps(element)) continue;
          exits.addAll(switch (element) {
            ForElement(forLoopParts: final ForEachParts parts) => _copies(
              '${_loopVariable(parts)} in ${_source(parts.iterable)}',
              parts.iterable,
              element,
              element.body,
              into,
              scope,
            ),
            _ => _expression(element, into, scope),
          });
        }
        return exits;
      case MethodInvocation(
        :final target?,
        methodName: SimpleIdentifier(name: 'map'),
        argumentList: ArgumentList(
          arguments: [final FunctionExpression closure],
        ),
      ):
        final parameter = closure.parameters?.parameters.firstOrNull;
        return _copies(
          '${parameter?.name?.lexeme ?? '_'} in ${_source(target)}',
          target,
          futures,
          closure,
          into,
          scope,
        );
      default:
        return _expression(futures, into, scope);
    }
  }

  /// Copies of [body], one per item of [items], that run side by side; drawn
  /// at [at].
  List<_Out> _copies(
    String label,
    Expression items,
    AstNode at,
    AstNode body,
    List<_Out> into,
    _Scope scope,
  ) {
    final before = _expression(items, into, scope);
    final copies = _add(
      _Copies(label, _Body(_package).ofCopy(body), _package._place(at)),
    );
    _connect(before, copies);
    return [(copies, null)];
  }

  /// The children of [node] in the order they run.
  List<_Out> _children(AstNode node, List<_Out> into, _Scope scope) {
    var current = into;
    for (final child in node.childEntities.whereType<AstNode>()) {
      current = child is Statement
          ? _statement(child, current, scope)
          : _expression(child, current, scope);
    }
    return current;
  }

  // ---- building the graph -----------------------------------------------------

  _Step _step(MethodInvocation e) {
    final first = e.argumentList.arguments.first;
    final name = switch (first) {
      StringLiteral(:final stringValue) => stringValue,
      _ => null,
    };
    if (name == null) {
      _package._warn(
        e,
        'step name is not a string literal',
        offset: e.methodName.offset,
      );
    }
    return _add(
      _Step(
        name ?? _source(first),
        _package._place(e, offset: e.methodName.offset),
      ),
    );
  }

  _Fork _fork(String label, AstNode at, List<String> outcomes) =>
      _add(_Fork(label, outcomes, _package._place(at)));

  _Join _join() => _add(_Join());

  T _add<T extends _V>(T v) {
    _vertices.add(v);
    return v;
  }

  void _connect(List<_Out> from, _V to) {
    for (final (v, outcome) in from) {
      (_edges[v] ??= []).add((outcome, to));
    }
  }

  /// Whether an edge leads to [v].
  bool _isEntered(_V v) =>
      _edges.values.any((edges) => edges.any((edge) => identical(edge.$2, v)));

  // ---- the body in the graph file ---------------------------------------------

  GraphBody _emit() {
    // A fork whose outcomes all lead to the same nodes decides nothing that
    // can be seen: it is not drawn, as a join. An outcome without an edge
    // (a throw) leads nowhere, which differs from anywhere.
    final hidden = <_V>{..._vertices.whereType<_Join>()};
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
    // Node ids: decimal, in the order the nodes were made.
    final ids = <_Drawn, String>{};
    for (final v in _vertices.whereType<_Drawn>()) {
      if (!hidden.contains(v)) ids[v] = '${ids.length + 1}';
    }
    final edges = <GraphEdge>[];
    final seen = <(String?, String?, String?)>{};
    void edgesOf(_V from, String? fromId) {
      for (final (label, to) in _edges[from] ?? const <(String?, _V)>[]) {
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

/// The outcomes of an `if`, a loop condition, `?:`, `&&` and `||`.
const _ifOutcomes = ['true', 'false'];

bool _isTrue(Expression e) => e is BooleanLiteral && e.value;

/// Whether a case matches every value: `_` or `var x`, untyped, unguarded.
bool _matchesAll(GuardedPattern pattern) =>
    pattern.whenClause == null &&
    switch (pattern.pattern) {
      WildcardPattern(type: null) ||
      DeclaredVariablePattern(type: null) => true,
      _ => false,
    };

/// Whether a switch on [e] matches every value without a `default`: Dart
/// requires it for `bool`, enums and sealed types.
bool _isExhaustive(Expression e) {
  final element = e.staticType?.element;
  return element is EnumElement ||
      (element is ClassElement && element.isSealed) ||
      e.staticType?.isDartCoreBool == true;
}

bool _isWithin(AstNode node, AstNode ancestor) {
  for (AstNode? n = node; n != null; n = n.parent) {
    if (identical(n, ancestor)) return true;
  }
  return false;
}
