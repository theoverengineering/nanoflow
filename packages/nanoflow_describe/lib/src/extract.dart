// Reads the functions with effects of a package from its resolved sources,
// without running them: every effect a function can take and every way between
// them (spec §7.1). Ported from prototypes/static_graph, which inlined the
// functions it called; here a call is a node, and the function it calls has a
// graph of its own.
//
// A body is followed statement by statement; what is left of its control flow
// between `Flow.effect` calls, calls of functions with effects and copies run
// by `Future.wait` are the edges. An `if`, a loop and a `switch` are forks,
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

  /// The functions with effects and the workflows by id, sorted by id.
  Map<String, GraphFunction> functions,

  /// The bodies of [functions], in the same order.
  List<FunctionBody> bodies,

  /// What could not be drawn, each once.
  List<GraphWarning> warnings,
});

/// The functions with effects of the package whose sources are [units].
///
/// [paths] gives the path from the package root of every unit by its absolute
/// path. [session] resolved [units]; a function outside them that a source
/// calls with a `Flow` is read through it to tell whether it has effects.
Future<Extracted> extract(
  List<ResolvedUnitResult> units,
  Map<String, String> paths,
  AnalysisSession session,
) async {
  final package = _Package(units, paths);
  await package._findEffectsOutside(session);
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
      _libraryOf = {for (final unit in _units) unit.unit: unit.libraryElement},
      _libraries = {for (final unit in _units) unit.libraryElement};

  final List<ResolvedUnitResult> _units;

  /// The path from the package root of every unit.
  final Map<CompilationUnit, String> _paths;

  /// The text of every unit.
  final Map<CompilationUnit, String> _contents;

  /// The library of every unit, whose types its code uses.
  final Map<CompilationUnit, LibraryElement> _libraryOf;
  final Set<LibraryElement> _libraries;

  final _declarations = <ExecutableElement, _Declaration>{};

  /// The methods of the sources that override a method, by the method.
  final _overriders = <ExecutableElement, Set<_Declaration>>{};

  /// Whether a class of the sources extends or implements [element].
  bool _isExtended(ClassElement element) => _extendedMemo[element] ??= _units
      .expand((unit) => unit.libraryElement.classes)
      .any(
        (c) => c != element && c.allSupertypes.any((t) => t.element == element),
      );
  final _extendedMemo = <ClassElement, bool>{};

  /// The functions with effects, once [_findWithEffects] has found them.
  final _withEffects = <_Declaration>{};

  /// The functions outside the sources that call effects.
  final _effectsOutside = <ExecutableElement>{};

  final _effectsMemo = <AstNode, bool>{};

  /// A set: a `finally` drawn once per way out of its try would repeat the
  /// warnings of its effects.
  final _warnings = <GraphWarning>{};

  /// Reads the functions outside the sources that the sources call with a
  /// `Flow`, to warn that their effects are not drawn.
  Future<void> _findEffectsOutside(AnalysisSession session) async {
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
      if (body != null && _callsEffectItself(body)) _effectsOutside.add(callee);
    }
  }

  Extracted _extract() {
    _index();
    _findWithEffects();
    final workflows = <_Declaration>{};
    for (final unit in _units) {
      _walk(unit.unit, (node) => _look(node, workflows));
    }
    final drawn = {..._withEffects, ...workflows}.toList()
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
      bodies: [for (final d in drawn) d.body],
      warnings: _warnings.toList(),
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
      InstanceElement(name: final name?) => '$name.',
      InstanceElement() => '${_unnamedExtension(body)}.',
      _ => '',
    };
    _declarations[element.baseElement] = _Declaration(
      '${_paths[body.root]}#$container${name.lexeme}',
      name.lexeme,
      _place(body, offset: name.offset),
      body,
    );
  }

  /// Finds the functions with effects: those that call an effect and, until
  /// nothing changes, those that call one of them.
  void _findWithEffects() {
    final callees = <_Declaration, Set<_Declaration>>{};
    for (final declaration in _declarations.values) {
      var effects = false;
      final calls = callees[declaration] = {};
      _walkRunning(declaration.body, (node) {
        if (node is MethodInvocation && isEffect(node)) effects = true;
        calls.addAll(_candidates(node));
      });
      if (effects) _withEffects.add(declaration);
    }
    for (var changed = true; changed;) {
      changed = false;
      for (final MapEntry(key: declaration, value: calls) in callees.entries) {
        if (!_withEffects.contains(declaration) &&
            calls.any(_withEffects.contains)) {
          _withEffects.add(declaration);
          changed = true;
        }
      }
    }
  }

  /// Takes the workflows and the warnings of the whole sources from [node],
  /// in a function with effects or not.
  void _look(AstNode node, Set<_Declaration> workflows) {
    switch (node) {
      case final FunctionExpression closure
          when closure.parent is! FunctionDeclaration &&
              !_runsHere(closure) &&
              _hasEffects(closure.body):
        _warn(closure, 'effects in a closure passed on are not drawn');
      case final FunctionDeclaration local
          when local.parent is FunctionDeclarationStatement &&
              _hasEffects(local.functionExpression.body):
        _warn(
          local,
          'effects in a local function are not drawn',
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
        when _effectsOutside.contains(callee)) {
      _warn(
        node,
        'effects of ${callee.name} are not drawn: '
        'it is outside the package sources',
      );
    }
  }

  // ---- effects and calls ------------------------------------------------------

  /// Whether running [node] can call an effect: a closure written in it does
  /// not run there, a function with effects it calls does.
  bool _hasEffects(AstNode node) => _effectsMemo[node] ??= _findsEffects(node);

  bool _findsEffects(AstNode node) {
    if (node is FunctionExpression && !_runsHere(node)) return false;
    if (node is MethodInvocation && isEffect(node)) return true;
    if (_callTargets(node).isNotEmpty) return true;
    return node.childEntities.whereType<AstNode>().any(_hasEffects);
  }

  /// The ids of the functions with effects that [node] calls, sorted: one for a
  /// function, every implementation for a method of an interface.
  List<String> _callTargets(AstNode node) => [
    for (final d in _candidates(node))
      if (_withEffects.contains(d)) d.id,
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

  /// Whether [body] calls `Flow.effect` where it runs.
  bool _callsEffectItself(FunctionBody body) {
    var effects = false;
    _walkRunning(body, (node) {
      if (node is MethodInvocation && isEffect(node)) effects = true;
    });
    return effects;
  }

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

  /// Whether [futures] is the first positional argument of `Future.wait`.
  bool _isWaited(Expression futures) {
    final node = _outermost(futures);
    final parent = node.parent;
    return parent is ArgumentList &&
        _firstPositional(parent) == node &&
        _isFutureWait(parent.parent!);
  }

  /// What the catch clauses of [s] do with a throw of [type] from its body
  /// (spec §7.1); a [type] of `null` is not known, and only a clause that
  /// catches anything surely takes it.
  ///
  /// The first clause the throw surely fits — one without a type, or with a
  /// type that [type] is a subtype of — decides: it takes the throw on after
  /// [s] when its block can finish normally, leaves the function when the
  /// block ends in `return`, and throws on, what it rethrows or throws, when
  /// the block ends in `rethrow` or `throw`. Without such a clause the throw
  /// goes on out as it is.
  (_Fate, DartType?) _fateOf(TryStatement s, DartType? type) {
    final library = _libraryOf[s.root]!;
    for (final clause in s.catchClauses) {
      final on = clause.exceptionType?.type;
      if (on != null &&
          !library.typeSystem.isSubtypeOf(
            type ?? library.typeProvider.objectType,
            on,
          )) {
        continue;
      }
      return switch (clause.body.statements.lastOrNull) {
        ReturnStatement() => (_Fate.returns, null),
        ExpressionStatement(expression: RethrowExpression()) => (
          _Fate.thrown,
          type,
        ),
        ExpressionStatement(expression: ThrowExpression(:final expression)) => (
          _Fate.thrown,
          expression.staticType,
        ),
        _ => (_Fate.caught, null),
      };
    }
    return (_Fate.thrown, type);
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

  /// The code of [node] as it is written, on one line (see [oneLine]).
  String _source(AstNode node) =>
      oneLine(_contents[node.root]!.substring(node.offset, node.end));

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
}

/// Whether [node] calls `Flow.effect` (of `package:nanoflow`).
bool isEffect(MethodInvocation node) => _isFlow(node, const {'effect'});

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

/// [code] on one line: a line break and the indents around it are one space,
/// none after an opening bracket or before a closing one, where a trailing
/// comma goes too (`a &&⏎    b` is `a && b`, `f(⏎  x,⏎)` is `f(x)`).
String oneLine(String code) => code
    .replaceAllMapped(RegExp(r'([(\[{])\s*\n\s*'), (m) => m[1]!)
    .replaceAllMapped(RegExp(r',?\s*\n\s*([)\]}])'), (m) => m[1]!)
    .replaceAll(RegExp(r'\s*\n\s*'), ' ');

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

/// Where a variable a `switch` goes by takes a value the path from here on
/// knows (spec 2026-10-08): a constant, an instance of exactly one class
/// ([_Exact]), or `null` when it is not known. The entry of a case is one
/// too: the value is the case's. Not drawn.
final class _Set extends _V {
  _Set(this.variable, this.value);
  final Element variable;
  final (Object?,)? value;

  /// The ways out of a fork that lead here, not linked until a way leads on
  /// from here: so the edges of a switch keep the order they are taken in,
  /// as they did when they led into the bodies straight.
  List<_Out>? waiting;
}

/// What a path knows a variable holds: an instance whose class is exactly
/// [element], made by one of its generative constructors (`Write(launch)`).
final class _Exact {
  const _Exact(this.element);
  final InterfaceElement element;

  @override
  bool operator ==(Object other) => other is _Exact && other.element == element;

  @override
  int get hashCode => element.hashCode;
}

/// Whether a case matches a value a path knows: surely, surely not, or it
/// cannot tell.
enum _Match { yes, no, maybe }

/// A case of a switch, by whether it matches a value a path knows.
typedef _Matcher = _Match Function(Object? value);

/// A `switch` on a variable the paths into it may know the value of: each
/// of its bodies, with its cases in order and the point the body is entered
/// at.
final class _Threaded {
  _Threaded(this.variable, this.fork);
  final Element variable;
  final _Fork fork;
  final cases = <(List<_Matcher> members, _Set entry)>[];

  /// Where a path that knows [value] enters: the body of the first case that
  /// matches it, as Dart tries them; `null` when a case before it may or may
  /// not match, or none does.
  _Set? entryFor((Object?,) value) {
    for (final (members, entry) in cases) {
      for (final matches in members) {
        switch (matches(value.$1)) {
          case _Match.yes:
            return entry;
          case _Match.maybe:
            return null;
          case _Match.no:
        }
      }
    }
    return null;
  }
}

/// A point drawn as a node, unless it is a fork that decides nothing.
sealed class _Drawn extends _V {
  _Drawn(this.place);
  final String place;

  GraphNode node(String id);
}

final class _Effect extends _Drawn {
  _Effect(this.name, super.place);
  final String name;

  @override
  GraphNode node(String id) => EffectNode(id: id, place: place, name: name);
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

/// Where `return`, `break`, `continue` and `throw` lead from the current
/// statement.
final class _Scope {
  const _Scope({
    this.returns,
    this.breaks = const {},
    this.continues = const {},
    this.throws,
  });

  /// Ways out of a `return`; `null` in the body itself, where a `return`
  /// leaves the body.
  final List<_Out>? returns;

  /// Ways out of a `break` by the statement it leaves.
  final Map<AstNode, List<_Out>> breaks;

  /// Where a `continue` goes by the loop it continues.
  final Map<AstNode, _V> continues;

  /// The innermost `try` whose body holds the statement, which a `throw`
  /// there goes to; `null` where there is none and the path ends.
  final _Try? throws;

  _Scope loop(AstNode loop, List<_Out> breaks, _V continues) => _Scope(
    returns: returns,
    breaks: {...this.breaks, loop: breaks},
    continues: {...this.continues, loop: continues},
    throws: throws,
  );

  _Scope breaking(AstNode statement, List<_Out> breaks) => _Scope(
    returns: returns,
    breaks: {...this.breaks, statement: breaks},
    continues: continues,
    throws: throws,
  );

  _Scope catching(_Try throws) => _Scope(
    returns: returns,
    breaks: breaks,
    continues: continues,
    throws: throws,
  );
}

/// What a catch clause does with a throw: takes it on after its `try`,
/// leaves the function with a `return`, or throws on.
enum _Fate { caught, returns, thrown }

/// A `try` as a `throw` in its body sees it (spec §7.1): a catch clause may
/// take the throw on after the `try`, turn it into a `return`, or let it go
/// on out to the `try` around it.
final class _Try {
  _Try(
    this._package,
    this._statement,
    this._outer, {
    required this.returns,
    required this.leaves,
  });

  final _Package _package;
  final TryStatement _statement;

  /// The `try` around this one.
  final _Try? _outer;

  /// Takes the ways out of a throw that a catch clause turns into a
  /// `return`.
  final void Function(List<_Out> exits) returns;

  /// Takes the ways out of a throw that leaves the `try` for the one around
  /// it, with the type of what it throws then.
  final void Function(List<_Out> exits, DartType? type) leaves;

  /// The ways out of the throws a catch clause takes on after the `try`.
  final caught = <_Out>[];

  /// Sends [exits], which throw a [type], where the catch clauses send
  /// them; a throw that nothing takes on ends its path.
  void send(List<_Out> exits, DartType? type) {
    switch (_package._fateOf(_statement, type)) {
      case (_Fate.caught, _):
        caught.addAll(exits);
      case (_Fate.returns, _):
        returns(exits);
      case (_Fate.thrown, final thrown) when _outer?.leads(thrown) ?? false:
        leaves(exits, thrown);
      case _:
      // Nothing takes it on: the path ends here.
    }
  }

  /// Whether a throw of [type] from the body goes anywhere but out of the
  /// function: a catch clause here or around takes it on or returns.
  bool leads(DartType? type) => switch (_package._fateOf(_statement, type)) {
    (_Fate.thrown, final thrown) => _outer?.leads(thrown) ?? false,
    _ => true,
  };
}

/// The graph of one body: a function's or a copy's.
final class _Body {
  _Body(this._package);

  final _Package _package;

  final _entry = _Entry();
  final _exit = _Exit();
  final _vertices = <_V>[];
  final _edges = <_V, List<(String?, _V)>>{};

  /// The points an edge leads to each point from.
  final _preds = <_V, List<_V>>{};

  /// The local variables a `switch` of the body goes by that nothing sets
  /// but a statement of the body itself: a path that knows the value of one
  /// goes straight into the case it takes (spec 2026-10-08).
  var _tracked = <Element>{};

  /// The head of a `while (true)` whose body is a `switch` on a tracked
  /// variable, until that switch takes it on: the paths into the head go
  /// each into its case.
  _Join? _pendingHead;

  /// The switch the paths into a loop head go straight into.
  final _threaded = <_V, _Threaded>{};

  GraphBody ofFunction(FunctionBody body) {
    _tracked = _trackedIn(body);
    _connect(_body(body, [(_entry, null)], const _Scope()), _exit);
    return _emit();
  }

  /// The graph of one copy whose body is [body]: a closure or an
  /// expression.
  GraphBody ofCopy(AstNode body) {
    _tracked = _trackedIn(body);
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
    // No effect, no jump out of it and no value a switch goes by: the flow
    // goes through as if it were not there.
    if (!_package._hasEffects(s) && !_jumpsOut(s) && !_setsTracked(s)) {
      return into;
    }
    switch (s) {
      case ExpressionStatement(expression: final AssignmentExpression e)
          when _trackedTarget(e) != null:
        return _set(
          _trackedTarget(e)!,
          e.operator.type == TokenType.EQ ? _valueOf(e.rightHandSide) : null,
          _expression(e, into, scope),
        );
      case VariableDeclarationStatement(:final variables)
          when variables.variables.any(_isTrackedDeclaration):
        var current = _expression(variables, into, scope);
        for (final v in variables.variables) {
          if (!_isTrackedDeclaration(v)) continue;
          current = _set(v.declaredFragment!.element, switch (v.initializer) {
            final i? => _valueOf(i),
            null => null,
          }, current);
        }
        return current;
      case Block():
        return _statements(s.statements, into, scope);
      case ReturnStatement():
        _return(switch (s.expression) {
          final e? => _expression(e, into, scope),
          null => into,
        }, scope);
        return const [];
      case ExpressionStatement(expression: final ThrowExpression e):
        return _throw(
          _children(e, into, scope),
          e.expression.staticType,
          scope,
        );
      case ExpressionStatement(expression: final RethrowExpression e):
        return _throw(_children(e, into, scope), null, scope);
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
        final breaks = <_Out>[];
        final inner = scope.loop(s, breaks, head);
        if (_isTrue(s.condition) && _threadsInto(s.body)) {
          // The head joins nothing: every path into the loop, from before it,
          // a `continue` or the end of its body, goes into the case it knows.
          _pendingHead = head;
          _connect(_statement(s.body, [...into, (head, null)], inner), head);
          return breaks;
        }
        _connect(into, head);
        final condition = _expression(s.condition, [(head, null)], scope);
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

  /// Throws a [type] (`null` when not known) from [exits]: the `try` around
  /// them sends them on (see [_Try]); without one the flow ends here, as a
  /// failure, and no edge leaves.
  List<_Out> _throw(List<_Out> exits, DartType? type, _Scope scope) {
    scope.throws?.send(exits, type);
    return const [];
  }

  /// The body, then `finally`: every way out of the body, a `return`, a
  /// `break` or a `continue` too, goes through `finally` before it goes on.
  /// `finally` is drawn once for each way out the body takes: the end of the
  /// body and the throws a catch takes on share one. A `throw` in the body
  /// goes where its catch clause (not drawn) sends it (see [_Try]), through
  /// `finally` when it leaves the `try`.
  List<_Out> _try(TryStatement s, List<_Out> into, _Scope scope) {
    if (s.catchClauses.isNotEmpty &&
        (_package._hasEffects(s.body) ||
            s.catchClauses.any((c) => _package._hasEffects(c.body)))) {
      _package._warn(s.catchClauses.first, 'catch clauses are not drawn');
    }
    final finallyBlock = s.finallyBlock;
    if (finallyBlock == null) {
      final caught = _Try(
        _package,
        s,
        scope.throws,
        returns: (exits) => _return(exits, scope),
        leaves: (exits, type) => _throw(exits, type, scope),
      );
      return [
        ..._statement(s.body, into, scope.catching(caught)),
        ...caught.caught,
      ];
    }
    // The jumps out of the body stop here first, and so do the throws that
    // leave it, by what they throw.
    final returns = <_Out>[];
    final leaving = <DartType?, List<_Out>>{};
    final caught = _Try(
      _package,
      s,
      scope.throws,
      returns: returns.addAll,
      leaves: (exits, type) => (leaving[type] ??= []).addAll(exits),
    );
    final jumps = _Scope(
      returns: returns,
      breaks: {for (final target in scope.breaks.keys) target: []},
      continues: {for (final target in scope.continues.keys) target: _join()},
      throws: caught,
    );
    final exits = _statement(s.body, into, jumps);
    final after = _statement(finallyBlock, [...exits, ...caught.caught], scope);
    if (returns.isNotEmpty) {
      _return(_statement(finallyBlock, returns, scope), scope);
    }
    for (final MapEntry(key: type, value: thrown) in leaving.entries) {
      _throw(_statement(finallyBlock, thrown, scope), type, scope);
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
    if (_trackedSubject(s) case final variable?) {
      return _switchOn(s, variable, into, scope);
    }
    final (fork, labels, matchesAll) = _switchFork(s);
    _connect(_expression(s.expression, into, scope), fork);
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

  /// The fork of the switch [s], the labels of its members in order, and
  /// whether they match every value (an exhaustive switch or a `default`,
  /// `case _`): without, the fork has a `default` outcome of its own.
  (_Fork, List<String>, bool) _switchFork(SwitchStatement s) {
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
    final fork = _fork('switch (${_source(s.expression)})', s.expression, [
      ...labels,
      if (!matchesAll) 'default',
    ]);
    return (fork, labels, matchesAll);
  }

  /// A switch on [variable], a tracked one: a path that knows the value goes
  /// straight into the body of the case it takes, the fork is drawn for the
  /// paths that do not. Each body is entered where the value is the case's.
  List<_Out> _switchOn(
    SwitchStatement s,
    Element variable,
    List<_Out> into,
    _Scope scope,
  ) {
    final (fork, labels, matchesAll) = _switchFork(s);
    final threaded = _Threaded(variable, fork);
    // Cases with no statements of their own share the body of the next one.
    final bodies = <(SwitchMember, _Set)>[];
    var pending = <int>[];
    for (final (i, member) in s.members.indexed) {
      pending.add(i);
      if (member.statements.isEmpty && i < s.members.length - 1) continue;
      final members = [for (final j in pending) s.members[j]];
      final entry = _add(
        _Set(variable, members.length == 1 ? _valueIn(members.single) : null),
      )..waiting = [for (final j in pending) (fork, labels[j])];
      threaded.cases.add(([for (final m in members) _matcher(m)], entry));
      bodies.add((member, entry));
      pending = [];
    }
    if (_pendingHead case final head?) {
      _threaded[head] = threaded;
      _pendingHead = null;
    }
    _thread(into, threaded, fork);
    final breaks = <_Out>[];
    final inner = scope.breaking(s, breaks);
    final exits = <_Out>[];
    for (final (member, entry) in bodies) {
      exits.addAll(_statements(member.statements, [(entry, null)], inner));
    }
    if (!matchesAll) exits.add((fork, 'default'));
    return [...exits, ...breaks];
  }

  /// Leads each of [from] into the case of [threaded] it knows the value for,
  /// and the rest to [otherwise].
  void _thread(List<_Out> from, _Threaded threaded, _V otherwise) {
    for (final out in from) {
      final value = _valueAt(out.$1, threaded.variable);
      final entry = value == null ? null : threaded.entryFor(value);
      _link([out], entry ?? otherwise);
    }
  }

  /// The value of [variable] every way back from [v] agrees on, or `null`
  /// when a way back reaches the entry, a point that lost it or a value not
  /// known. A case's entry knows its own value.
  (Object?,)? _valueAt(_V v, Element variable) {
    final seen = <_V>{};
    final values = <(Object?,)>{};
    var unknown = false;
    void back(_V v) {
      if (unknown || !seen.add(v)) return;
      if (v is _Set && v.variable == variable) {
        if (v.value case final value?) {
          values.add(value);
        } else {
          unknown = true;
        }
        return;
      }
      final preds = _preds[v];
      if (v is _Entry || preds == null || preds.isEmpty) {
        unknown = true;
        return;
      }
      preds.forEach(back);
    }

    back(v);
    return !unknown && values.length == 1 ? values.single : null;
  }

  /// A point where [variable] takes [value] on the way from [into].
  List<_Out> _set(Element variable, (Object?,)? value, List<_Out> into) {
    final set = _add(_Set(variable, value));
    _connect(into, set);
    return [(set, null)];
  }

  /// The tracked variable [e] assigns, or `null`.
  Element? _trackedTarget(AssignmentExpression e) => switch (e.leftHandSide) {
    SimpleIdentifier(:final element?) when _tracked.contains(element) =>
      element,
    _ => null,
  };

  bool _isTrackedDeclaration(VariableDeclaration v) =>
      _tracked.contains(v.declaredFragment?.element);

  /// The tracked variable [s] goes by, or `null`.
  Element? _trackedSubject(SwitchStatement s) =>
      switch (s.expression.unParenthesized) {
        SimpleIdentifier(:final element?) when _tracked.contains(element) =>
          element,
        _ => null,
      };

  /// Whether [body], a `while (true)`'s, is a switch on a tracked variable
  /// (or starts with one) that is drawn.
  bool _threadsInto(Statement body) {
    final first = switch (body) {
      SwitchStatement() => body,
      Block(:final statements) when statements.isNotEmpty => statements.first,
      _ => null,
    };
    return first is SwitchStatement &&
        _trackedSubject(first) != null &&
        (_package._hasEffects(first) ||
            _jumpsOut(first) ||
            _setsTracked(first));
  }

  /// Whether a statement of [s] (not of a closure in it) sets a tracked
  /// variable.
  bool _setsTracked(Statement s) {
    if (_tracked.isEmpty) return false;
    var sets = false;
    void visit(AstNode node) {
      if (sets) return;
      switch (node) {
        case FunctionExpression():
          return;
        case ExpressionStatement(expression: final AssignmentExpression e)
            when _trackedTarget(e) != null:
          sets = true;
        case VariableDeclaration() when _isTrackedDeclaration(node):
          sets = true;
        default:
          for (final child in node.childEntities.whereType<AstNode>()) {
            visit(child);
          }
      }
    }

    visit(s);
    return sets;
  }

  /// The local variables and parameters a `switch` in [root] goes by, less
  /// those something else than a statement of [root] itself assigns: a
  /// closure, a local function, an expression.
  Set<Element> _trackedIn(AstNode root) {
    final subjects = <Element>{};
    _walk(root, (node) {
      if (node case SwitchStatement(:final expression)) {
        if (expression.unParenthesized case SimpleIdentifier(:final element?)
            when element is LocalVariableElement ||
                element is FormalParameterElement) {
          subjects.add(element);
        }
      }
    });
    if (subjects.isEmpty) return subjects;
    void visit(AstNode node, bool nested) {
      switch (node) {
        case AssignmentExpression(
              leftHandSide: SimpleIdentifier(:final element?),
            )
            when subjects.contains(element) &&
                (nested || node.parent is! ExpressionStatement):
          subjects.remove(element);
        case FunctionExpression() when !identical(node, root):
          nested = true;
        default:
      }
      for (final child in node.childEntities.whereType<AstNode>()) {
        visit(child, nested);
      }
    }

    visit(root, false);
    return subjects;
  }

  /// The value [e] gives a variable a path follows: a constant ([_constOf]),
  /// or an instance of exactly one class, made by a generative constructor
  /// of a class that is not abstract; `null` otherwise.
  (Object?,)? _valueOf(Expression e) {
    if (_constOf(e) case final c?) return c;
    if (e.unParenthesized case InstanceCreationExpression(
      :final constructorName,
    )) {
      final constructor = constructorName.element;
      final type = constructorName.type.element;
      if (constructor != null &&
          !constructor.isFactory &&
          type is ClassElement &&
          !type.isAbstract) {
        return (_Exact(type),);
      }
    }
    return null;
  }

  /// Whether [member] matches a value a path knows ([_valueOf]).
  _Matcher _matcher(SwitchMember member) {
    _Matcher constant((Object?,)? c) => c == null
        ? (_) => _Match.maybe
        : (v) => v is _Exact
              ? _Match.no
              : v == c.$1
              ? _Match.yes
              : _Match.no;
    switch (member) {
      case SwitchDefault():
        return (_) => _Match.yes;
      case SwitchCase(:final expression):
        return constant(_constOf(expression));
      case SwitchPatternCase(:final guardedPattern):
        if (_matchesAll(guardedPattern)) return (_) => _Match.yes;
        if (guardedPattern.whenClause != null) return (_) => _Match.maybe;
        switch (guardedPattern.pattern) {
          case ConstantPattern(:final expression):
            return constant(_constOf(expression));
          case final ObjectPattern pattern:
            final type = pattern.type.element;
            if (type is! InterfaceElement) return (_) => _Match.maybe;
            // Of another class it surely does not match; of this one, only
            // when its fields match whatever they hold.
            final fields = _irrefutableFields(pattern);
            return (v) => switch (v) {
              _Exact(:final element)
                  when element == type ||
                      element.allSupertypes.any((t) => t.element == type) =>
                fields ? _Match.yes : _Match.maybe,
              _Exact() => _Match.no,
              _ => _Match.maybe,
            };
          default:
            return (_) => _Match.maybe;
        }
    }
  }

  /// The value a path entering the body of [member] knows: the constant it
  /// names, or the class it names when that class is final and nothing in
  /// the package extends or implements it; `null` otherwise.
  (Object?,)? _valueIn(SwitchMember member) => switch (member) {
    SwitchCase(:final expression) => _constOf(expression),
    SwitchPatternCase(
      guardedPattern: GuardedPattern(whenClause: null, :final pattern),
    ) =>
      switch (pattern) {
        ConstantPattern(:final expression) => _constOf(expression),
        ObjectPattern(:final type)
            when _irrefutableFields(pattern) &&
                type.element is ClassElement &&
                (type.element! as ClassElement).isFinal &&
                !_package._isExtended(type.element! as ClassElement) =>
          (_Exact(type.element! as ClassElement),),
        _ => null,
      },
    _ => null,
  };

  /// Whether every field of [pattern] matches whatever the field holds:
  /// `:final x`, `x: var y`, `_`, untyped.
  bool _irrefutableFields(ObjectPattern pattern) => pattern.fields.every(
    (field) => switch (field.pattern) {
      DeclaredVariablePattern(type: null) ||
      WildcardPattern(type: null) => true,
      _ => false,
    },
  );

  /// The constant [e] is, as a switch case names it: a `bool`, `int`,
  /// `String` or `null` literal, or a value of an enum; `null` otherwise.
  (Object?,)? _constOf(Expression e) => switch (e.unParenthesized) {
    BooleanLiteral(:final value) => (value,),
    IntegerLiteral(:final value) => (value,),
    SimpleStringLiteral(:final value) => (value,),
    NullLiteral() => (null,),
    PrefixedIdentifier(:final identifier) => _enumValue(identifier.element),
    PropertyAccess(:final propertyName) => _enumValue(propertyName.element),
    SimpleIdentifier(:final element) => _enumValue(element),
    _ => null,
  };

  /// The value of an enum [element] names: the field, or its getter, which
  /// a reference such as `Stage.write` resolves to.
  (Object?,)? _enumValue(Element? element) {
    final field = switch (element) {
      PropertyAccessorElement(:final variable) => variable,
      _ => element,
    };
    return field is FieldElement && field.isEnumConstant ? (field,) : null;
  }

  /// Whether [s] has a `return`, a `throw` that no `catch` in [s] takes on
  /// (see [_Package._fateOf]), or a `break` or `continue` that leaves it.
  /// `catch` clauses are not drawn, so what they hold does not count.
  bool _jumpsOut(Statement s) {
    var jumps = false;
    // [tries]: the `try` statements in [s] around [node], innermost last.
    void visit(AstNode node, List<TryStatement> tries) {
      if (jumps) return;
      switch (node) {
        case FunctionExpression():
          return; // a return in a closure leaves the closure, not s
        case TryStatement(:final body, :final finallyBlock):
          visit(body, [...tries, node]);
          if (finallyBlock != null) visit(finallyBlock, tries);
        case ExpressionStatement(
          expression: ThrowExpression(:final expression),
        ):
          jumps = _leaves(tries, expression.staticType);
        case ExpressionStatement(expression: RethrowExpression()):
          jumps = _leaves(tries, null);
        case ReturnStatement():
          jumps = true;
        case BreakStatement(:final target) || ContinueStatement(:final target):
          jumps = target == null || !_isWithin(target, s);
        default:
          for (final child in node.childEntities.whereType<AstNode>()) {
            visit(child, tries);
          }
      }
    }

    visit(s, const []);
    return jumps;
  }

  /// Whether a throw of [type] in the bodies of [tries], innermost last,
  /// leaves them: as a throw, or as a `return` of a catch clause.
  bool _leaves(List<TryStatement> tries, DartType? type) {
    var thrown = type;
    for (final s in tries.reversed) {
      switch (_package._fateOf(s, thrown)) {
        case (_Fate.caught, _):
          return false;
        case (_Fate.returns, _):
          return true;
        case (_Fate.thrown, final next):
          thrown = next;
      }
    }
    return true;
  }

  // ---- expressions ------------------------------------------------------------

  List<_Out> _expression(AstNode e, List<_Out> into, _Scope scope) {
    // A closure's body does not run where the closure is written, unless it
    // is called right there; that call draws it.
    if (into.isEmpty || !_package._hasEffects(e)) return into;
    switch (e) {
      case MethodInvocation() when isEffect(e):
        final effect = _effect(e);
        _connect(into, effect);
        return [(effect, null)];
      case MethodInvocation() when _package._isFutureWait(e):
        final futures = _firstPositional(e.argumentList);
        if (futures == null) return into;
        return _parallel(futures, into, scope);
      case FunctionExpressionInvocation(:final function)
          when function.unParenthesized is FunctionExpression:
        // A closure called in place: its body runs here.
        final closure = function.unParenthesized as FunctionExpression;
        final arguments = _expression(e.argumentList, into, scope);
        final returns = <_Out>[];
        final exits = _body(
          closure.body,
          arguments,
          _Scope(returns: returns, throws: scope.throws),
        );
        return [...exits, ...returns];
      case PropertyAccess(target: RecordLiteral(:final fields))
          when _package._isRecordWait(e):
        // `(a, b).wait`: each field starts here, side by side.
        return [
          for (final field in fields)
            if (_package._hasEffects(field)) ..._expression(field, into, scope),
        ];
      case ConditionalExpression():
        final condition = _expression(e.condition, into, scope);
        final fork = _fork(_source(e.condition), e.condition, _ifOutcomes);
        _connect(condition, fork);
        return [
          ..._arm(e.thenExpression, [(fork, 'true')], scope),
          ..._arm(e.elseExpression, [(fork, 'false')], scope),
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
            ..._arm(c.expression, [(fork, labels[i])], scope),
        ];
      case BinaryExpression(:final operator)
          when (operator.type == TokenType.AMPERSAND_AMPERSAND ||
                  operator.type == TokenType.BAR_BAR) &&
              _package._hasEffects(e.rightOperand):
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

  /// An arm of `?:` or of a switch expression: one that is a `throw` ends
  /// its path, as a `throw` statement does.
  List<_Out> _arm(Expression arm, List<_Out> into, _Scope scope) {
    final exits = _expression(arm, into, scope);
    return switch (arm.unParenthesized) {
      ThrowExpression(:final expression) => _throw(
        exits,
        expression.staticType,
        scope,
      ),
      _ => exits,
    };
  }

  /// What `Future.wait` over [futures] runs: each element of a list starts
  /// here, a `for` element or a `map` runs copies of its body; the flow goes
  /// on when all are done.
  List<_Out> _parallel(Expression futures, List<_Out> into, _Scope scope) {
    switch (futures) {
      case ListLiteral(:final elements):
        final exits = <_Out>[];
        for (final element in elements) {
          if (!_package._hasEffects(element)) continue;
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

  _Effect _effect(MethodInvocation e) {
    final first = e.argumentList.arguments.first;
    final name = switch (first) {
      StringLiteral(:final stringValue) => stringValue,
      _ => null,
    };
    if (name == null) {
      _package._warn(
        e,
        'effect name is not a string literal',
        offset: e.methodName.offset,
      );
    }
    return _add(
      _Effect(
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

  /// Leads [from] to [to]; to the cases they know when [to] is the head of
  /// a loop over a switch (see [_threadsInto]).
  void _connect(List<_Out> from, _V to) {
    if (_threaded[to] case final threaded?) {
      _thread(from, threaded, to);
    } else {
      _link(from, to);
    }
  }

  void _link(List<_Out> from, _V to) {
    for (final (v, outcome) in from) {
      if (v case _Set(:final waiting?)) {
        v.waiting = null;
        _link(waiting, v);
      }
      (_edges[v] ??= []).add((outcome, to));
      (_preds[to] ??= []).add(v);
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
    // What no path from the entry reaches — a case no path takes, the fork
    // of a switch every path knows — is not drawn either.
    final reached = <_V>{};
    for (final queue = <_V>[_entry]; queue.isNotEmpty;) {
      final v = queue.removeLast();
      if (!reached.add(v)) continue;
      for (final (_, to) in _edges[v] ?? const <(String?, _V)>[]) {
        queue.add(to);
      }
    }
    final hidden = <_V>{
      ..._vertices.whereType<_Join>(),
      ..._vertices.whereType<_Set>(),
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
/// come before it, as in `Future.wait(eagerError: true, [ … ])`.
Expression? _firstPositional(ArgumentList arguments) => arguments.arguments
    .where((argument) => argument is! NamedArgument)
    .firstOrNull
    ?.argumentExpression;

/// The name in an id of the unnamed extension that [node] is in:
/// `<extension>` for the first unnamed extension of its file,
/// `<extension 2>` for the second, and so on.
String _unnamedExtension(AstNode node) {
  final extension = node.thisOrAncestorOfType<ExtensionDeclaration>()!;
  final unnamed = [
    for (final declaration in (node.root as CompilationUnit).declarations)
      if (declaration is ExtensionDeclaration && declaration.name == null)
        declaration,
  ];
  final n = unnamed.indexOf(extension) + 1;
  return n == 1 ? '<extension>' : '<extension $n>';
}

bool _isWithin(AstNode node, AstNode ancestor) {
  for (AstNode? n = node; n != null; n = n.parent) {
    if (identical(n, ancestor)) return true;
  }
  return false;
}
