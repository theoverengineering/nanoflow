/// Reads the graph of a workflow function from its code, without running
/// it: every step it can take and every way between them.
///
/// The function's control flow is followed statement by statement; what is
/// left of it between `Flow.step` calls are the arrows. An `if`, a loop and
/// a `switch` are forks, labelled with their source; `Future.wait` over
/// steps is a split; a call to a function of the same library that takes
/// steps is followed into its body.
library;

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:path/path.dart' as p;

/// What [extractGraph] read: the graph in the README format, and what it
/// could not draw.
typedef Extracted = ({Map<String, Object?> graph, List<String> warnings});

/// The graph of [function], a top-level function of [file].
///
/// Throws a [FormatException] when [file] has compile errors or no such
/// function.
Future<Extracted> extractGraph(String file, String function) async {
  final path = p.normalize(p.absolute(file));
  final collection = AnalysisContextCollection(includedPaths: [path]);
  final session = collection.contextFor(path).currentSession;
  final library = await session.getResolvedLibrary(path);
  if (library is! ResolvedLibraryResult) {
    throw FormatException('cannot resolve $path');
  }
  final errors = [
    for (final unit in library.units)
      for (final d in unit.diagnostics)
        if (d.severity == Severity.error) '${unit.path}: ${d.message}',
  ];
  if (errors.isNotEmpty) throw FormatException(errors.join('\n'));
  final unit = library.units.firstWhere((u) => u.path == path);
  final declaration = unit.unit.declarations
      .whereType<FunctionDeclaration>()
      .where((d) => d.name.lexeme == function)
      .firstOrNull;
  if (declaration == null) {
    throw FormatException('no top-level function $function in $path');
  }
  return _Builder(library, p.dirname(path)).build(declaration);
}

/// A point of the control flow.
sealed class _V {}

final class _Start extends _V {}

/// Where the run ends.
final class _End extends _V {}

/// Where ways meet: a loop's head, the end of a `do` body. Not drawn.
final class _Join extends _V {}

final class _Step extends _V {
  _Step(this.name, this.place);
  final String name;
  final String place;
}

final class _Fork extends _V {
  _Fork(this.label, this.place, {required this.ifForm});
  final String label;
  final String place;

  /// Outcomes `true` and `false`, drawn as `then` and `else`; otherwise the
  /// outcomes are the cases of a switch.
  final bool ifForm;
}

/// A way out of a point that does not lead anywhere yet, with the outcome
/// it is taken on when the point is a fork.
typedef _Exit = (_V, String?);

/// Where `return`, `break` and `continue` lead from the current statement.
final class _Scope {
  const _Scope({
    this.returns,
    this.breaks,
    this.continues,
    this.inlining = const {},
  });

  /// Exits of a `return`: `null` at the top, where it ends the run.
  final List<_Exit>? returns;
  final List<_Exit>? breaks;
  final _V? continues;

  /// Functions being followed into, to stop at recursion.
  final Set<ExecutableElement> inlining;

  _Scope loop(List<_Exit> breaks, _V continues) => _Scope(
    returns: returns,
    breaks: breaks,
    continues: continues,
    inlining: inlining,
  );

  _Scope switchBody(List<_Exit> breaks) => _Scope(
    returns: returns,
    breaks: breaks,
    continues: continues,
    inlining: inlining,
  );
}

final class _Builder {
  _Builder(this._library, this._dir);

  final ResolvedLibraryResult _library;
  final String _dir;

  final _start = _Start();
  final _end = _End();
  final _vertices = <_V>[];
  final _edges = <_V, List<(String?, _V)>>{};
  final _warnings = <String>[];
  final _stepsMemo = <AstNode, bool>{};

  Extracted build(FunctionDeclaration function) {
    final body = function.functionExpression.body;
    final exits = _body(body, [(_start, null)], const _Scope());
    _connect(exits, _end);
    return (graph: _emit(), warnings: _warnings);
  }

  // ---- statements ---------------------------------------------------------

  List<_Exit> _body(FunctionBody body, List<_Exit> into, _Scope scope) =>
      switch (body) {
        BlockFunctionBody(:final block) => _statement(block, into, scope),
        ExpressionFunctionBody(:final expression) => _expression(
          expression,
          into,
          scope,
        ),
        _ => into,
      };

  List<_Exit> _statements(
    Iterable<Statement> statements,
    List<_Exit> into,
    _Scope scope,
  ) {
    var current = into;
    for (final statement in statements) {
      current = _statement(statement, current, scope);
    }
    return current;
  }

  List<_Exit> _statement(Statement s, List<_Exit> into, _Scope scope) {
    if (into.isEmpty) return into; // unreachable
    switch (s) {
      case Block():
        return _statements(s.statements, into, scope);
      case ExpressionStatement():
        return _expression(s.expression, into, scope);
      case VariableDeclarationStatement():
        var current = into;
        for (final v in s.variables.variables) {
          if (v.initializer case final init?) {
            current = _expression(init, current, scope);
          }
        }
        return current;
      case ReturnStatement():
        final exits = switch (s.expression) {
          final e? => _expression(e, into, scope),
          null => into,
        };
        if (scope.returns case final returns?) {
          returns.addAll(exits);
        } else {
          _connect(exits, _end);
        }
        return const [];
      case IfStatement():
        final condition = _expression(s.expression, into, scope);
        final label = switch (s.caseClause) {
          final c? => '${s.expression.toSource()} ${c.toSource()}',
          null => s.expression.toSource(),
        };
        final fork = _fork(label, s.expression, ifForm: true);
        _connect(condition, fork);
        final thenExits = _statement(s.thenStatement, [(fork, 'true')], scope);
        final elseExits = switch (s.elseStatement) {
          final e? => _statement(e, [(fork, 'false')], scope),
          null => <_Exit>[(fork, 'false')],
        };
        return [...thenExits, ...elseExits];
      case WhileStatement():
        final head = _join();
        _connect(into, head);
        final condition = _expression(s.condition, [(head, null)], scope);
        final breaks = <_Exit>[];
        final List<_Exit> bodyEntry;
        final List<_Exit> out;
        if (_isTrue(s.condition)) {
          bodyEntry = condition;
          out = const [];
        } else {
          final fork = _fork(
            'while (${s.condition.toSource()})',
            s.condition,
            ifForm: true,
          );
          _connect(condition, fork);
          bodyEntry = [(fork, 'true')];
          out = [(fork, 'false')];
        }
        _connect(_statement(s.body, bodyEntry, scope.loop(breaks, head)), head);
        return [...out, ...breaks];
      case DoStatement():
        final head = _join();
        final next = _join();
        _connect(into, head);
        final breaks = <_Exit>[];
        _connect(
          _statement(s.body, [(head, null)], scope.loop(breaks, next)),
          next,
        );
        final condition = _expression(s.condition, [(next, null)], scope);
        if (_isTrue(s.condition)) {
          _connect(condition, head);
          return breaks;
        }
        final fork = _fork(
          'while (${s.condition.toSource()})',
          s.condition,
          ifForm: true,
        );
        _connect(condition, fork);
        _connect([(fork, 'true')], head);
        return [(fork, 'false'), ...breaks];
      case ForStatement():
        return _for(s, into, scope);
      case SwitchStatement():
        return _switch(s, into, scope);
      case BreakStatement():
        scope.breaks?.addAll(into);
        return const [];
      case ContinueStatement():
        if (scope.continues case final c?) _connect(into, c);
        return const [];
      case TryStatement():
        _warn(s, 'catch clauses are not drawn: a step that throws ends here');
        final exits = _statement(s.body, into, scope);
        return switch (s.finallyBlock) {
          final f? => _statement(f, exits, scope),
          null => exits,
        };
      default:
        return _children(s, into, scope);
    }
  }

  List<_Exit> _for(ForStatement s, List<_Exit> into, _Scope scope) {
    final parts = s.forLoopParts;
    final breaks = <_Exit>[];
    switch (parts) {
      case ForEachParts():
        final current = _expression(parts.iterable, into, scope);
        final head = _join();
        _connect(current, head);
        final fork = _fork(
          'for ${_loopVariable(parts)} in ${parts.iterable.toSource()}',
          parts.iterable,
          ifForm: true,
        );
        _connect([(head, null)], fork);
        _connect(
          _statement(s.body, [(fork, 'true')], scope.loop(breaks, head)),
          head,
        );
        return [(fork, 'false'), ...breaks];
      case ForParts():
        var current = into;
        switch (parts) {
          case ForPartsWithDeclarations(:final variables):
            for (final v in variables.variables) {
              if (v.initializer case final init?) {
                current = _expression(init, current, scope);
              }
            }
          case ForPartsWithExpression(:final initialization?):
            current = _expression(initialization, current, scope);
          case ForPartsWithPattern(:final variables):
            current = _expression(variables.expression, current, scope);
          default:
        }
        final head = _join();
        final next = _join();
        _connect(current, head);
        final List<_Exit> bodyEntry;
        final List<_Exit> out;
        if (parts.condition case final c?) {
          final condition = _expression(c, [(head, null)], scope);
          final fork = _fork('for (; ${c.toSource()};)', c, ifForm: true);
          _connect(condition, fork);
          bodyEntry = [(fork, 'true')];
          out = [(fork, 'false')];
        } else {
          bodyEntry = [(head, null)];
          out = const [];
        }
        _connect(_statement(s.body, bodyEntry, scope.loop(breaks, next)), next);
        var updated = <_Exit>[(next, null)];
        for (final u in parts.updaters) {
          updated = _expression(u, updated, scope);
        }
        _connect(updated, head);
        return [...out, ...breaks];
    }
  }

  List<_Exit> _switch(SwitchStatement s, List<_Exit> into, _Scope scope) {
    final current = _expression(s.expression, into, scope);
    final fork = _fork(
      'switch (${s.expression.toSource()})',
      s.expression,
      ifForm: false,
    );
    _connect(current, fork);
    final breaks = <_Exit>[];
    final exits = <_Exit>[];
    final pending = <String>[];
    var matchesAll = _isExhaustive(s.expression);
    for (final member in s.members) {
      pending.add(switch (member) {
        SwitchDefault() => 'default',
        SwitchCase(:final expression) => expression.toSource(),
        SwitchPatternCase(:final guardedPattern) => guardedPattern.toSource(),
      });
      if (member is SwitchDefault) matchesAll = true;
      // An empty case shares the body of the next one.
      if (member.statements.isEmpty) continue;
      final entry = [for (final label in pending) (fork, label)];
      pending.clear();
      exits.addAll(
        _statements(member.statements, entry, scope.switchBody(breaks)),
      );
    }
    if (!matchesAll) exits.add((fork, 'default'));
    return [...exits, ...breaks];
  }

  // ---- expressions --------------------------------------------------------

  List<_Exit> _expression(AstNode e, List<_Exit> into, _Scope scope) {
    if (into.isEmpty) return into;
    if (e is FunctionExpression) {
      // A closure's body does not run where the closure is written, unless
      // it is called right there; that call draws it.
      if (!_runsHere(e) && _containsSteps(e.body, const {})) {
        _warn(e, 'steps in a closure passed on are not drawn');
      }
      return into;
    }
    if (!_hasSteps(e)) return into;
    switch (e) {
      case MethodInvocation() when _isStep(e):
        final step = _step(e);
        _connect(into, step);
        return [(step, null)];
      case MethodInvocation() when _isFutureWait(e):
        return _parallel(
          e.argumentList.arguments.first.argumentExpression,
          into,
          scope,
        );
      case FunctionExpressionInvocation(:final function)
          when function.unParenthesized is FunctionExpression:
        // An async closure called in place: its body runs here.
        final closure = function.unParenthesized as FunctionExpression;
        final args = _expression(e.argumentList, into, scope);
        final returns = <_Exit>[];
        final exits = _body(
          closure.body,
          args,
          _Scope(returns: returns, inlining: scope.inlining),
        );
        return [...exits, ...returns];
      case ConditionalExpression():
        final condition = _expression(e.condition, into, scope);
        final fork = _fork(e.condition.toSource(), e.condition, ifForm: true);
        _connect(condition, fork);
        return [
          ..._expression(e.thenExpression, [(fork, 'true')], scope),
          ..._expression(e.elseExpression, [(fork, 'false')], scope),
        ];
      case BinaryExpression(:final operator)
          when (operator.type == TokenType.AMPERSAND_AMPERSAND ||
                  operator.type == TokenType.BAR_BAR) &&
              _hasSteps(e.rightOperand):
        final left = _expression(e.leftOperand, into, scope);
        final fork = _fork(
          e.leftOperand.toSource(),
          e.leftOperand,
          ifForm: true,
        );
        _connect(left, fork);
        final evaluates = operator.type == TokenType.AMPERSAND_AMPERSAND
            ? 'true'
            : 'false';
        final skips = evaluates == 'true' ? 'false' : 'true';
        return [
          ..._expression(e.rightOperand, [(fork, evaluates)], scope),
          (fork, skips),
        ];
      default:
        if (_calleeBody(e) case (final callee, final body)?) {
          if (!scope.inlining.contains(callee)) {
            final args = _children(e, into, scope);
            final returns = <_Exit>[];
            final exits = _body(
              body,
              args,
              _Scope(returns: returns, inlining: {...scope.inlining, callee}),
            );
            return [...exits, ...returns];
          }
          _warn(e, 'recursive call to ${callee.name} is not followed');
        }
    }
    return _children(e, into, scope);
  }

  /// What `Future.wait` over [futures] runs: each element of a list starts
  /// here, a `for` element or a `map` starts a copy of its body for each
  /// item; the run goes on when all are done.
  List<_Exit> _parallel(Expression futures, List<_Exit> into, _Scope scope) {
    switch (futures) {
      case ListLiteral(:final elements):
        final exits = <_Exit>[];
        for (final element in elements) {
          if (!_hasSteps(element)) continue;
          exits.addAll(switch (element) {
            ForElement(forLoopParts: final ForEachParts parts) => _copies(
              '${_loopVariable(parts)} in ${parts.iterable.toSource()}',
              parts.iterable,
              element.body,
              into,
              scope,
            ),
            _ => _expression(element, into, scope),
          });
        }
        return exits.isEmpty ? into : exits;
      case MethodInvocation(
        :final target?,
        methodName: SimpleIdentifier(name: 'map'),
        argumentList: ArgumentList(
          arguments: [final FunctionExpression closure],
        ),
      ):
        final parameter = closure.parameters?.parameters.firstOrNull;
        return _copies(
          '${parameter?.name?.lexeme ?? '_'} in ${target.toSource()}',
          target,
          closure,
          into,
          scope,
        );
      default:
        return _expression(futures, into, scope);
    }
  }

  /// Copies of [body] that run side by side, one per item of [items]: a
  /// fork into the body, and past it when there are no items.
  List<_Exit> _copies(
    String label,
    Expression items,
    AstNode body,
    List<_Exit> into,
    _Scope scope,
  ) {
    final source = _expression(items, into, scope);
    final fork = _fork('∥ for $label', items, ifForm: true);
    _connect(source, fork);
    final entry = <_Exit>[(fork, 'true')];
    final List<_Exit> exits;
    if (body is FunctionExpression) {
      final returns = <_Exit>[];
      exits = [
        ..._body(
          body.body,
          entry,
          _Scope(returns: returns, inlining: scope.inlining),
        ),
        ...returns,
      ];
    } else {
      exits = _expression(body, entry, scope);
    }
    return [...exits, (fork, 'false')];
  }

  String _loopVariable(ForEachParts parts) => switch (parts) {
    ForEachPartsWithDeclaration(:final loopVariable) =>
      loopVariable.name.lexeme,
    ForEachPartsWithIdentifier(:final identifier) => identifier.name,
    ForEachPartsWithPattern(:final pattern) => pattern.toSource(),
  };

  /// Whether [closure] runs where it is written: called in place, or given
  /// to `map` whose copies `Future.wait` runs.
  bool _runsHere(FunctionExpression closure) {
    AstNode? node = closure;
    while (node?.parent is ParenthesizedExpression) {
      node = node!.parent;
    }
    final parent = node?.parent;
    return (parent is FunctionExpressionInvocation &&
            parent.function == node) ||
        (parent is ArgumentList &&
            parent.parent is MethodInvocation &&
            (parent.parent! as MethodInvocation).methodName.name == 'map');
  }

  /// The children of [node] in the order they run.
  List<_Exit> _children(AstNode node, List<_Exit> into, _Scope scope) {
    var current = into;
    for (final child in node.childEntities.whereType<AstNode>()) {
      current = child is Statement
          ? _statement(child, current, scope)
          : _expression(child, current, scope);
    }
    return current;
  }

  // ---- recognising steps and calls ----------------------------------------

  bool _isStep(MethodInvocation e) {
    final method = e.methodName.element;
    return method is MethodElement &&
        method.name == 'step' &&
        method.enclosingElement?.name == 'Flow' &&
        method.library.uri.toString() == 'package:static_graph/flow.dart';
  }

  bool _isFutureWait(MethodInvocation e) {
    final method = e.methodName.element;
    return method is MethodElement &&
        method.name == 'wait' &&
        method.enclosingElement?.name == 'Future' &&
        method.library.uri.toString() == 'dart:async';
  }

  /// The function [node] calls and its body, when the body is in this
  /// library.
  (ExecutableElement, FunctionBody)? _calleeBody(AstNode node) {
    final callee = switch (node) {
      MethodInvocation() => node.methodName.element,
      FunctionExpressionInvocation() => node.element,
      _ => null,
    };
    if (callee is! ExecutableElement) return null;
    final declaration = callee.library == _library.element
        ? _library.getFragmentDeclaration(callee.firstFragment)?.node
        : null;
    final body = switch (declaration) {
      FunctionDeclaration(:final functionExpression) => functionExpression.body,
      MethodDeclaration(:final body) => body,
      _ => null,
    };
    if (body == null || body is EmptyFunctionBody) {
      if (_takesFlow(callee)) {
        _warn(node, 'steps of ${callee.name} are not drawn: no body here');
      }
      return null;
    }
    return (callee, body);
  }

  bool _takesFlow(ExecutableElement e) => e.formalParameters.any(
    (parameter) => parameter.type.element?.name == 'Flow',
  );

  bool _hasSteps(AstNode? node) =>
      node != null && (_stepsMemo[node] ??= _containsSteps(node, const {}));

  /// Whether running [node] can take a step: a closure written in it does
  /// not run there, a function it calls does.
  bool _containsSteps(AstNode node, Set<ExecutableElement> visiting) {
    if (node is FunctionExpression &&
        node.parent is! FunctionDeclaration &&
        !_runsHere(node)) {
      return false;
    }
    if (node is MethodInvocation && _isStep(node)) return true;
    if (_calleeBodyQuiet(node) case (final callee, final body)?
        when !visiting.contains(callee)) {
      if (_containsSteps(body, {...visiting, callee})) return true;
    }
    return node.childEntities.whereType<AstNode>().any(
      (child) => _containsSteps(child, visiting),
    );
  }

  (ExecutableElement, FunctionBody)? _calleeBodyQuiet(AstNode node) {
    final warnings = _warnings.length;
    final result = _calleeBody(node);
    _warnings.length = warnings;
    return result;
  }

  bool _isTrue(Expression e) => e is BooleanLiteral && e.value;

  /// Whether a switch on [e] matches every value without a `default`: Dart
  /// requires it for `bool`, enums and sealed types.
  bool _isExhaustive(Expression e) {
    final element = e.staticType?.element;
    return element is EnumElement ||
        (element is ClassElement && element.isSealed) ||
        e.staticType?.isDartCoreBool == true;
  }

  // ---- building the graph -------------------------------------------------

  _Step _step(MethodInvocation e) {
    final first = e.argumentList.arguments.firstOrNull;
    final name = switch (first) {
      SimpleStringLiteral(:final value) => value,
      _ => null,
    };
    if (name == null) _warn(e, 'a step name must be a string literal');
    return _add(_Step(name ?? e.toSource(), _place(e)));
  }

  _Fork _fork(String label, AstNode at, {required bool ifForm}) =>
      _add(_Fork(label, _place(at), ifForm: ifForm));

  _Join _join() => _add(_Join());

  T _add<T extends _V>(T v) {
    _vertices.add(v);
    return v;
  }

  void _connect(List<_Exit> from, _V to) {
    for (final (v, outcome) in from) {
      (_edges[v] ??= []).add((outcome, to));
    }
  }

  String _place(AstNode node) {
    final unit = node.root as CompilationUnit;
    final file = unit.declaredFragment!.source.fullName;
    final line = unit.lineInfo.getLocation(node.offset).lineNumber;
    return '${p.relative(file, from: _dir)}:$line';
  }

  void _warn(AstNode node, String message) =>
      _warnings.add('${_place(node)}: $message');

  // ---- the README format --------------------------------------------------

  Map<String, Object?> _emit() {
    // A fork whose outcomes all lead to the same nodes decides nothing that
    // can be seen: drop it, as a join.
    final hidden = <_V>{..._vertices.whereType<_Join>()};
    for (var changed = true; changed;) {
      changed = false;
      for (final fork in _vertices.whereType<_Fork>()) {
        if (hidden.contains(fork)) continue;
        final outcomes = _outcomes(fork, hidden).values.toList();
        if (_allSame(outcomes)) {
          hidden.add(fork);
          changed = true;
        }
      }
    }
    final names = _names(hidden);
    Object target(Set<_V> to) {
      final named = [
        for (final v in _vertices)
          if (to.contains(v) && names.containsKey(v)) names[v]!,
      ];
      return named.length == 1 ? named.single : named;
    }

    final nodes = <String, Object?>{};
    for (final v in _vertices) {
      final name = names[v];
      if (name == null) continue;
      switch (v) {
        case _Step():
          final next = _resolve(_targets(v), hidden);
          nodes[name] = {
            'command': v.place,
            if (next.any((t) => t is! _End)) 'then': target(next),
          };
        case _Fork():
          final outcomes = _outcomes(v, hidden);
          if (v.ifForm) {
            final otherwise = outcomes['false'] ?? {_end};
            nodes[name] = {
              'decide': v.place,
              'then': target(outcomes['true'] ?? {_end}),
              if (otherwise.any((t) => t is! _End)) 'else': target(otherwise),
            };
          } else {
            final otherwise = outcomes.remove('default');
            nodes[name] = {
              'decide': v.place,
              'then': {
                for (final MapEntry(:key, :value) in outcomes.entries)
                  key: target(value),
              },
              if (otherwise != null && otherwise.any((t) => t is! _End))
                'else': target(otherwise),
            };
          }
        default:
      }
    }
    return {
      'start': target(_resolve(_targets(_start), hidden)),
      'nodes': nodes,
    };
  }

  Set<_V> _targets(_V v) => {
    for (final (_, to) in _edges[v] ?? const <(String?, _V)>[]) to,
  };

  Map<String, Set<_V>> _outcomes(_Fork fork, Set<_V> hidden) {
    final result = <String, Set<_V>>{};
    for (final (outcome, to) in _edges[fork] ?? const <(String?, _V)>[]) {
      (result[outcome!] ??= {}).addAll(_resolve({to}, hidden));
    }
    if (fork.ifForm) {
      // An outcome with no edge ends the run.
      result['true'] ??= {_end};
      result['false'] ??= {_end};
    }
    return result;
  }

  /// The drawn points [vs] lead to, through hidden ones.
  Set<_V> _resolve(Set<_V> vs, Set<_V> hidden, [Set<_V>? seen]) {
    seen ??= {};
    final result = <_V>{};
    for (final v in vs) {
      if (!hidden.contains(v)) {
        result.add(v);
      } else if (seen.add(v)) {
        result.addAll(_resolve(_targets(v), hidden, seen));
      }
    }
    return result;
  }

  bool _allSame(List<Set<_V>> sets) => sets.every(
    (s) => s.length == sets.first.length && s.containsAll(sets.first),
  );

  /// Unique node names: a step's own name, a fork's source; a repeated one
  /// gets `#2`, `#3`.
  Map<_V, String> _names(Set<_V> hidden) {
    final names = <_V, String>{};
    final used = <String, int>{};
    for (final v in _vertices) {
      if (hidden.contains(v)) continue;
      final base = switch (v) {
        _Step(:final name) => name,
        _Fork(:final label) => label,
        _ => null,
      };
      if (base == null) continue;
      final n = used[base] = (used[base] ?? 0) + 1;
      names[v] = n == 1 ? base : '$base#$n';
    }
    return names;
  }
}
