// Side effects outside effects (effects design §3, spec §7.1): what the routes
// of the graphs of a package run between their nodes that touches the world —
// the time, random numbers, anything of `dart:io` — themselves or through the
// functions of the package they call. Logs and waiting are free; a node is an
// effect, so nothing in its body counts.

import 'dart:math';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:nanoflow_model/nanoflow_model.dart';

import 'extract.dart';

/// The warnings about side effects outside effects in the routes whose bodies
/// are [routes], each once.
///
/// [units] are the resolved sources of the package; [paths] gives the path
/// from the package root of every unit by its absolute path. A side effect in
/// the body of a route warns where it is; a call there of a function of the
/// sources warns when the call reaches one, naming the first.
List<GraphWarning> sideEffectWarnings(
  List<ResolvedUnitResult> units,
  Map<String, String> paths,
  List<FunctionBody> routes,
) => _Check(units, paths, routes)._warnings();

/// What a side effect is to the rule: none, a log, which may be anywhere, or
/// one that belongs in an effect.
enum _Kind { none, log, sideEffect }

/// A side effect a call reaches: its code and `path:line`.
typedef _Reached = ({String source, String place});

/// What the walk of a function meets: a side effect, or a call of a function
/// of the sources that is not a route.
typedef _Meet = ({_Reached? sideEffect, Element? call});

final class _Check {
  _Check(
    List<ResolvedUnitResult> units,
    Map<String, String> paths,
    this._routes,
  ) : _units = {
        for (final unit in units)
          unit.unit: (path: paths[unit.path]!, content: unit.content),
      } {
    final routes = _routes.toSet();
    for (final unit in units) {
      _index(unit.unit, routes);
    }
  }

  final List<FunctionBody> _routes;

  /// The path from the package root and the text of every unit.
  final Map<CompilationUnit, ({String path, String content})> _units;

  /// What a function, method, constructor, getter or setter of the sources
  /// runs when it is called, by its element.
  final _runs = <Element, List<AstNode>>{};

  /// The top-level functions that are routes, whose side effects warn in
  /// their own bodies.
  final _routeFunctions = <Element>{};

  /// What a call of a function of the sources reaches, by the function; none
  /// for a function that reaches no side effect (see [_reachAll]).
  late final _reached = _reachAll();

  List<GraphWarning> _warnings() {
    final warnings = <GraphWarning>{};
    for (final body in _routes) {
      _walk(body, (node) {
        if (_isSideEffect(node)) {
          warnings.add(
            GraphWarning(
              place: _place(node),
              message: 'side effect outside an effect: ${_source(node)}',
            ),
          );
        } else if (_reached[_resolved(node)] case final reached?) {
          warnings.add(
            GraphWarning(
              place: _place(node),
              message:
                  'side effect outside an effect: ${_source(node)} '
                  'reaches ${reached.source} at ${reached.place}',
            ),
          );
        }
      });
    }
    return warnings.toList();
  }

  /// Finds what every function, method, constructor, getter and setter of
  /// [unit] with a body runs, and which are routes of [routes].
  void _index(CompilationUnit unit, Set<FunctionBody> routes) {
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
        if (routes.contains(runs.last)) _routeFunctions.add(element);
      }
      for (final child in node.childEntities.whereType<AstNode>()) {
        visit(child);
      }
    }

    visit(unit);
  }

  /// The first side effect that each function of the sources that is not a
  /// route reaches: the first that the walk of what it runs meets,
  /// in the order of its code, itself or through a call of another such
  /// function. Every function is walked once.
  ///
  /// Functions that call each other, around a ring, form a strongly connected
  /// component (Tarjan's algorithm), and all of them reach one side effect:
  /// the first that a walk from the member entered first meets, itself or
  /// through a call out of the ring, going into each member once, where it is
  /// called. A component is done after every component its calls lead to, so
  /// what those reach is known by then.
  Map<Element, _Reached> _reachAll() {
    final meets = {
      for (final MapEntry(key: function, value: runs) in _runs.entries)
        if (!_routeFunctions.contains(function)) function: _meets(runs),
    };
    final reached = <Element, _Reached>{};
    final order = <Element, int>{};
    final low = <Element, int>{};
    final stack = <Element>[];
    final onStack = <Element>{};

    /// The first side effect a walk from [function] through [component]
    /// meets: one of a member, or what a call out of the component reaches. A
    /// call of a member not in [met] yet goes into it, where it is.
    _Reached? walk(Element function, Set<Element> component, Set<Element> met) {
      met.add(function);
      for (final (:sideEffect, :call) in meets[function]!) {
        if (sideEffect != null) return sideEffect;
        if (!component.contains(call)) {
          if (reached[call] case final found?) return found;
        } else if (!met.contains(call)) {
          if (walk(call!, component, met) case final found?) return found;
        }
      }
      return null;
    }

    /// Enters [function] and the functions it calls, by Tarjan's algorithm.
    /// When [function] is the first member of its component entered, the
    /// component is done: all of it reaches what a walk from [function] meets.
    void enter(Element function) {
      final entered = order.length;
      order[function] = entered;
      low[function] = entered;
      stack.add(function);
      onStack.add(function);
      for (final (sideEffect: _, :call) in meets[function]!) {
        if (call == null) continue;
        if (!order.containsKey(call)) {
          enter(call);
          low[function] = min(low[function]!, low[call]!);
        } else if (onStack.contains(call)) {
          low[function] = min(low[function]!, order[call]!);
        }
      }
      if (low[function] != order[function]) return;
      final component = <Element>{};
      Element member;
      do {
        member = stack.removeLast();
        onStack.remove(member);
        component.add(member);
      } while (member != function);
      if (walk(function, component, {}) case final first?) {
        for (final member in component) {
          reached[member] = first;
        }
      }
    }

    for (final function in meets.keys) {
      if (!order.containsKey(function)) enter(function);
    }
    return reached;
  }

  /// What a walk of [runs] meets, in the order of the code.
  List<_Meet> _meets(List<AstNode> runs) {
    final meets = <_Meet>[];
    for (final part in runs) {
      _walk(part, (node) {
        if (_isSideEffect(node)) {
          meets.add((
            sideEffect: (source: _source(node), place: _place(node)),
            call: null,
          ));
        } else if (_resolved(node) case final function?
            when _runs.containsKey(function) &&
                !_routeFunctions.contains(function)) {
          meets.add((sideEffect: null, call: function));
        }
      });
    }
    return meets;
  }

  /// Calls [visit] on [node] and every node below it, in the order of the
  /// code. It leaves out a local function, which runs where it is called.
  void _walk(AstNode node, void Function(AstNode node) visit) {
    if (node is FunctionDeclarationStatement || node is Comment) return;
    visit(node);
    for (final child in node.childEntities.whereType<AstNode>()) {
      _walk(child, visit);
    }
  }

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
    InstanceCreationExpression(:final constructorName) ||
    ConstructorReference(:final constructorName) => constructorName.element,
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
/// `stdout` and `stderr`, which are logs, and for values that touch nothing:
/// constants (enum values too), exceptions and their members.
///
/// `dart:io` declares what it exports about HTTP in `dart:_http`, which only
/// `dart:io` exports.
_Kind _kindOf(Element? element) {
  if (element is! ExecutableElement) return _Kind.none;
  final type = element.enclosingElement?.name;
  return switch (element.library.uri.toString()) {
    'dart:io'
        when element is GetterElement &&
            element.enclosingElement is LibraryElement &&
            (element.name == 'stdout' || element.name == 'stderr') =>
      _Kind.log,
    'dart:io' || 'dart:_http' when _isValue(element) => _Kind.none,
    'dart:io' || 'dart:_http' => _Kind.sideEffect,
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

/// Whether [element] gives a value that touches nothing: it reads a constant
/// (an enum value is one), or makes an exception or an error, or is an
/// instance member of one — of a class with `Exception` or `Error` of
/// `dart:core` among its supertypes.
bool _isValue(ExecutableElement element) => switch (element) {
  PropertyAccessorElement(variable: PropertyInducingElement(isConst: true)) =>
    true,
  ConstructorElement(:final enclosingElement) => _isException(enclosingElement),
  ExecutableElement(
    isStatic: false,
    enclosingElement: final InterfaceElement type,
  ) =>
    _isException(type),
  _ => false,
};

bool _isException(InterfaceElement type) => type.allSupertypes.any(
  (supertype) =>
      (supertype.element.name == 'Exception' ||
          supertype.element.name == 'Error') &&
      supertype.element.library.uri.toString() == 'dart:core',
);
