/// Which node of a graph file written again is which node of the one
/// before (spec §9 «Граф»): node ids are numbers in the order the code has
/// the nodes, so an edit shifts them, while what a node is — an effect's
/// name, a call's functions, copies' label, a fork's condition — and its
/// place among the nodes alike stay. The levels opened and the nodes
/// expanded in place follow their nodes so. Pure.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'body_path.dart';

/// What [node] is, whatever its id: its kind and what it shows.
String _what(GraphNode node) => switch (node) {
  EffectNode(:final name) => 'effect $name',
  CallNode(:final functions) => 'call ${functions.join(',')}',
  CopiesNode(:final label) => 'copies $label',
  ConditionNode(:final label) => 'fork $label',
};

/// The key of [node] in [body]: what it is, and how many nodes before it in
/// the body are the same — `call lib/a.dart#f 1` for the second call of `f`.
String nodeKey(GraphBody body, GraphNode node) {
  final what = _what(node);
  var before = 0;
  for (final other in body.nodes) {
    if (identical(other, node) || other.id == node.id) break;
    if (_what(other) == what) before++;
  }
  return '$what $before';
}

/// The node of [body] whose [nodeKey] is [key]; `null` when there is none.
GraphNode? nodeOfKey(GraphBody body, String key) {
  for (final node in body.nodes) {
    if (nodeKey(body, node) == key) return node;
  }
  return null;
}

/// The keys of the nodes [path] opens from [workflow]'s body down, whose
/// calls go to [functions], with the function a call opens to: as far as
/// the levels go.
List<(String, String?)> pathKeys(
  GraphFunction workflow,
  Map<String, GraphFunction> functions,
  List<Opened> path,
) {
  final keys = <(String, String?)>[];
  var body = workflow.body;
  for (final opened in path) {
    final node = body.node(opened.nodeId);
    final level = levelOpened(body, opened, functions);
    if (node == null || level == null) break;
    keys.add((nodeKey(body, node), opened.functionId));
    body = level.body;
  }
  return keys;
}

/// The path that opens the nodes [keys] ([pathKeys]) from [workflow]'s
/// body, whose calls go to [functions]: as far as they are there, and
/// `complete` when all of them are.
({List<Opened> path, bool complete}) pathOfKeys(
  List<(String, String?)> keys,
  GraphFunction workflow,
  Map<String, GraphFunction> functions,
) {
  final path = <Opened>[];
  var body = workflow.body;
  for (final (key, functionId) in keys) {
    final node = nodeOfKey(body, key);
    if (node == null) break;
    final opened = Opened(node.id, functionId: functionId);
    final level = levelOpened(body, opened, functions);
    if (level == null) break;
    path.add(opened);
    body = level.body;
  }
  return (path: path, complete: path.length == keys.length);
}

/// [path], opened from [before]'s body with its [beforeFunctions], as the
/// same nodes open from [after]'s body with [afterFunctions]: as far as
/// they are there, and `complete` when all of them are.
({List<Opened> path, bool complete}) followPath(
  List<Opened> path, {
  required GraphFunction before,
  required Map<String, GraphFunction> beforeFunctions,
  required GraphFunction after,
  required Map<String, GraphFunction> afterFunctions,
}) {
  final keys = pathKeys(before, beforeFunctions, path);
  final followed = pathOfKeys(keys, after, afterFunctions);
  return (
    path: followed.path,
    complete: keys.length == path.length && followed.complete,
  );
}
