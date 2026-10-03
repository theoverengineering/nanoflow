/// The levels of the graph the canvas goes down through (spec §9 «Граф»,
/// decision 6): a workflow's body, then the body of a call or of copies
/// opened in it, and so on; one level is drawn at a time, the path to it
/// above as crumbs. Pure.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

/// A node of the shown body opened one level down: [nodeId], and for a call
/// which of its functions, [functionId].
final class Opened {
  const Opened(this.nodeId, {this.functionId});

  final String nodeId;

  /// The function a call is opened to; `null` for copies.
  final String? functionId;

  @override
  bool operator ==(Object other) =>
      other is Opened &&
      other.nodeId == nodeId &&
      other.functionId == functionId;

  @override
  int get hashCode => Object.hash(nodeId, functionId);

  @override
  String toString() => 'Opened($nodeId, functionId: $functionId)';
}

/// One level of the graph: a body, and what its crumb says.
final class BodyLevel {
  const BodyLevel._(this.title, this.body, this.opened);

  /// The crumb: the workflow's name (`review`), a function's with `()`
  /// ([functionTitle]), copies' label (`pkg in packages`).
  final String title;

  final GraphBody body;

  /// How the level above opened it; `null` for the workflow's body.
  final Opened? opened;
}

/// The title of the function [id] in a crumb or a choice: what follows `#`
/// in it, with `()`; `publish()`, `MailNotifier.notify()` for a method.
String functionTitle(String id) => '${id.substring(id.indexOf('#') + 1)}()';

/// What opening [node] can show, one level down: one choice for each
/// function of a call that [functions] has, in the call's order (several
/// for the implementations of an interface method); the body of copies;
/// nothing for a step or a condition.
List<Opened> openings(GraphNode node, Map<String, GraphFunction> functions) =>
    switch (node) {
      CallNode(:final id, functions: final ids) => [
        for (final function in ids)
          if (functions.containsKey(function)) Opened(id, functionId: function),
      ],
      CopiesNode(:final id) => [Opened(id)],
      StepNode() || ConditionNode() => const [],
    };

/// The levels [path] goes down through from [workflow]'s body, whose calls
/// go to [functions]: the workflow's body first, then one level for each
/// step of [path] while it opens a node of the level above that opens so
/// ([openings]); the rest of [path] is left out.
List<BodyLevel> bodyLevels(
  GraphFunction workflow,
  Map<String, GraphFunction> functions,
  List<Opened> path,
) {
  final levels = [BodyLevel._(workflow.name, workflow.body, null)];
  for (final opened in path) {
    final level = levelOpened(levels.last.body, opened, functions);
    if (level == null) break;
    levels.add(level);
  }
  return levels;
}

/// The level [opened] opens in [body], whose calls go to [functions]; `null`
/// when [body] has no such node, or it does not open so ([openings]).
BodyLevel? levelOpened(
  GraphBody body,
  Opened opened,
  Map<String, GraphFunction> functions,
) {
  final node = body.node(opened.nodeId);
  if (node == null || !openings(node, functions).contains(opened)) return null;
  return switch (node) {
    CopiesNode(:final label, :final body) => BodyLevel._(label, body, opened),
    _ => BodyLevel._(
      functionTitle(opened.functionId!),
      functions[opened.functionId]!.body,
      opened,
    ),
  };
}

/// The path to a level, as a key: another path, another key.
String levelKey(Iterable<Opened> path) =>
    [for (final opened in path) '${opened.nodeId}#${opened.functionId ?? ''}']
        .join('/');
