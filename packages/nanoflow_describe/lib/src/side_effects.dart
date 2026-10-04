// Side effects outside effects (effects design §3, spec §7.1): what the graph
// functions of a package run between their effects that touches the world —
// the time, random numbers, anything of `dart:io` — themselves or through the
// functions of the package they call. Logs and waiting are free; the body
// given to `Flow.effect` is the effect, so nothing in it counts.

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:nanoflow_model/nanoflow_model.dart';

import 'extract.dart';

/// The warnings about side effects outside effects in the graph functions
/// whose bodies are [graphBodies], each once.
///
/// [units] are the resolved sources of the package; [paths] gives the path
/// from the package root of every unit by its absolute path. A side effect in
/// the body of a graph function warns where it is; a call there of a function
/// of the sources warns when the call reaches one, naming the first.
List<GraphWarning> sideEffectWarnings(
  List<ResolvedUnitResult> units,
  Map<String, String> paths,
  List<FunctionBody> graphBodies,
) => _Check(units, paths, graphBodies)._warnings();

/// What a side effect is to the rule: none, a log, which may be anywhere, or
/// one that belongs in an effect.
enum _Kind { none, log, sideEffect }

/// A side effect a call reaches: its code and `path:line`.
typedef _Reached = ({String source, String place});

final class _Check {
  _Check(
    List<ResolvedUnitResult> units,
    Map<String, String> paths,
    this._graphBodies,
  ) : _units = {
        for (final unit in units)
          unit.unit: (path: paths[unit.path]!, content: unit.content),
      } {
    final graphBodies = _graphBodies.toSet();
    for (final unit in units) {
      _index(unit.unit, graphBodies);
    }
  }

  final List<FunctionBody> _graphBodies;

  /// The path from the package root and the text of every unit.
  final Map<CompilationUnit, ({String path, String content})> _units;

  /// What a function, method, constructor, getter or setter of the sources
  /// runs when it is called, by its element.
  final _runs = <Element, List<AstNode>>{};

  /// The graph functions, whose side effects warn in their own bodies.
  final _graphFunctions = <Element>{};

  /// What a call of a function of the sources reaches: the first side effect,
  /// or `null` for none.
  final _reached = <Element, _Reached?>{};

  /// The functions being walked: a call back into one reaches nothing more.
  final _walking = <Element>{};

  List<GraphWarning> _warnings() {
    final warnings = <GraphWarning>{};
    for (final body in _graphBodies) {
      _walk(body, (node) {
        if (_isSideEffect(node)) {
          warnings.add(
            GraphWarning(
              place: _place(node),
              message: 'side effect outside an effect: ${_source(node)}',
            ),
          );
        } else if (_reach(node) case final reached?) {
          warnings.add(
            GraphWarning(
              place: _place(node),
              message:
                  'side effect outside an effect: ${_source(node)} '
                  'reaches ${reached.source} at ${reached.place}',
            ),
          );
        }
        return false;
      });
    }
    return warnings.toList();
  }

  /// Finds what every function, method, constructor, getter and setter of
  /// [unit] with a body runs, and which are graph functions.
  void _index(CompilationUnit unit, Set<FunctionBody> graphBodies) {
    void visit(AstNode node) {
      final (fragment, runs) = switch (node) {
        FunctionDeclaration(
          :final declaredFragment,
          :final functionExpression,
        ) =>
          (declaredFragment, [functionExpression.body]),
        MethodDeclaration(:final declaredFragment, :final body) => (
          declaredFragment,
          [body],
        ),
        ConstructorDeclaration(
          :final declaredFragment,
          :final initializers,
          :final body,
        ) =>
          (declaredFragment, [...initializers, body]),
        _ => (null, const <AstNode>[]),
      };
      if (fragment != null) {
        final element = fragment.element.baseElement;
        _runs[element] = runs;
        if (graphBodies.contains(runs.last)) _graphFunctions.add(element);
      }
      for (final child in node.childEntities.whereType<AstNode>()) {
        visit(child);
      }
    }

    visit(unit);
  }

  /// The first side effect that [node] reaches when it calls a function of
  /// the sources that is not a graph function, by a depth-first walk of what
  /// that function runs in the order of its code; `null` for none.
  _Reached? _reach(AstNode node) {
    final element = _resolved(node);
    final runs = _runs[element];
    if (element == null || runs == null || _graphFunctions.contains(element)) {
      return null;
    }
    if (_reached.containsKey(element)) return _reached[element];
    if (!_walking.add(element)) return null;
    _Reached? reached;
    for (final part in runs) {
      final found = _walk(part, (node) {
        reached = _isSideEffect(node)
            ? (source: _source(node), place: _place(node))
            : _reach(node);
        return reached != null;
      });
      if (found) break;
    }
    _walking.remove(element);
    return _reached[element] = reached;
  }

  /// Calls [visit] on [node] and every node below it in the order of the
  /// code, until [visit] returns true, which this returns then. It leaves
  /// out the body given to `Flow.effect`, which is the effect, and a local
  /// function, which runs where it is called.
  bool _walk(AstNode node, bool Function(AstNode node) visit) {
    if (node is FunctionDeclarationStatement ||
        node is Comment ||
        _isEffectBody(node)) {
      return false;
    }
    if (visit(node)) return true;
    for (final child in node.childEntities.whereType<AstNode>()) {
      if (_walk(child, visit)) return true;
    }
    return false;
  }

  /// Whether [node] is the body given to `Flow.effect`.
  bool _isEffectBody(AstNode node) => switch (node.parent) {
    ArgumentList(:final arguments, parent: final MethodInvocation call) =>
      arguments.length > 1 && arguments[1] == node && isEffect(call),
    _ => false,
  };

  /// Whether [node] is a side effect that belongs in an effect, and the first
  /// of its chain: what it is a member of, however deep, is not one already,
  /// nor `stdout` or `stderr`, whose members are logs.
  bool _isSideEffect(AstNode node) {
    if (_kindOf(_resolved(node)) != _Kind.sideEffect) return false;
    for (var of = _receiver(node); of != null; of = _receiver(of)) {
      if (_kindOf(_resolved(of)) != _Kind.none) return false;
    }
    return true;
  }

  /// The function, method, constructor, getter or setter that [node] calls,
  /// reads or writes, as declared. A name that is part of a larger node — a
  /// member of a target, a named constructor, what is assigned — is resolved
  /// with that node.
  Element? _resolved(AstNode node) => switch (node) {
    InstanceCreationExpression(:final constructorName) =>
      constructorName.element,
    MethodInvocation(:final methodName) => methodName.element,
    PropertyAccess(:final propertyName) when !_isAssigned(node) =>
      propertyName.element,
    PrefixedIdentifier(:final identifier) when !_isAssigned(node) =>
      identifier.element,
    SimpleIdentifier(:final element) when _standsAlone(node) => element,
    AssignmentExpression(:final writeElement) => writeElement,
    _ => null,
  }?.baseElement;

  /// Whether [identifier] names something on its own, not as part of the
  /// node around it.
  bool _standsAlone(SimpleIdentifier identifier) => switch (identifier.parent) {
    MethodInvocation(:final methodName) => methodName != identifier,
    PrefixedIdentifier(:final prefix) => prefix == identifier,
    PropertyAccess(:final propertyName) => propertyName != identifier,
    ConstructorName() => false,
    _ => !_isAssigned(identifier),
  };

  /// Whether [node] is what an assignment assigns to.
  bool _isAssigned(AstNode node) => switch (node.parent) {
    AssignmentExpression(:final leftHandSide) => leftHandSide == node,
    _ => false,
  };

  /// The expression whose value [node] is a member of, or awaits.
  Expression? _receiver(AstNode node) => switch (node) {
    MethodInvocation(:final realTarget) => realTarget,
    PropertyAccess(:final realTarget) ||
    IndexExpression(:final realTarget) => realTarget,
    PrefixedIdentifier(:final prefix) => prefix,
    AssignmentExpression(:final leftHandSide) => _receiver(leftHandSide),
    AwaitExpression(:final expression) => expression,
    _ => null,
  }?.unParenthesized;

  /// The code of [node] as it is written, on one line.
  String _source(AstNode node) =>
      oneLine(_units[node.root]!.content.substring(node.offset, node.end));

  /// `path:line` of [node].
  String _place(AstNode node) {
    final unit = node.root as CompilationUnit;
    final line = unit.lineInfo.getLocation(node.offset).lineNumber;
    return '${_units[unit]!.path}:$line';
  }
}

/// What [element] is to the rule (effects design §3): the time
/// (`DateTime.now`, `DateTime.timestamp`, `Stopwatch`), random numbers (the
/// constructors of `Random` of `dart:math`) and every function, method,
/// constructor, getter and setter of `dart:io` are side effects, but for
/// `stdout` and `stderr`, which are logs.
///
/// `dart:io` declares some of what it exports elsewhere: everything HTTP in
/// `dart:_http`, which only `dart:io` exports, and `HttpStatus` in
/// `dart:_internal`.
_Kind _kindOf(Element? element) {
  if (element is! ExecutableElement) return _Kind.none;
  final type = element.enclosingElement?.name;
  return switch (element.library.uri.toString()) {
    'dart:io'
        when element is GetterElement &&
            element.enclosingElement is LibraryElement &&
            (element.name == 'stdout' || element.name == 'stderr') =>
      _Kind.log,
    'dart:io' || 'dart:_http' => _Kind.sideEffect,
    'dart:_internal' when type == 'HttpStatus' => _Kind.sideEffect,
    'dart:core'
        when element is ConstructorElement &&
            (type == 'Stopwatch' ||
                type == 'DateTime' &&
                    (element.name == 'now' || element.name == 'timestamp')) =>
      _Kind.sideEffect,
    'dart:math' when element is ConstructorElement && type == 'Random' =>
      _Kind.sideEffect,
    _ => _Kind.none,
  };
}
