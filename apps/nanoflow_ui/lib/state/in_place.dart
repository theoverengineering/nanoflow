/// Calls and copies expanded in place (spec §9 «Граф», decision 6): a
/// node of the body drawn shows its body in a frame, without leaving the
/// level; the nodes of that body expand in turn, at any depth. Pure.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'body_path.dart';

/// The nodes expanded in place in the bodies of one graph screen's graph:
/// for the body at each path — the levels opened down to it, then the
/// frames it is in — the nodes of it expanded, each as it opens
/// ([openings]).
final class Expansions {
  /// By [levelKey] of a body's path, its expanded nodes by id.
  final Map<String, Map<String, Opened>> _at = {};

  /// Whether nothing is expanded anywhere.
  bool get isEmpty => _at.isEmpty;

  /// The nodes expanded in the body at [path], in the order expanded.
  List<Opened> at(List<Opened> path) => [...?_at[levelKey(path)]?.values];

  /// Expands [node], a node of the body at [path]: drawn in place, as it
  /// opens. Another opening of the same node gives way to it.
  void expand(List<Opened> path, Opened node) =>
      (_at[levelKey(path)] ??= {})[node.nodeId] = node;

  /// Collapses the node [nodeId] of the body at [path] back to its tile,
  /// and forgets what was expanded in its frame.
  void collapse(List<Opened> path, String nodeId) {
    final key = levelKey(path);
    final node = _at[key]?.remove(nodeId);
    if (_at[key]?.isEmpty ?? false) _at.remove(key);
    if (node == null) return;
    final inside = levelKey([...path, node]);
    _at.removeWhere((k, _) => k == inside || k.startsWith('$inside/'));
  }

  /// Collapses every node.
  void clear() => _at.clear();
}

/// A node of a body drawn on the canvas, expanded in place: its body in a
/// frame, and the nodes of that body expanded in turn.
final class InPlaceFrame {
  InPlaceFrame._(this.node, this.levels, List<InPlaceFrame> frames)
    : frames = List.unmodifiable(frames);

  /// The call or the copies expanded.
  final GraphNode node;

  /// The levels down to the frame's body: those opened down to the level
  /// drawn, those of the frames round it, and its own, last. Copies frames
  /// among them number their copies as when they are opened so.
  final List<BodyLevel> levels;

  /// The nodes of the frame's body expanded in place.
  final List<InPlaceFrame> frames;

  String get nodeId => node.id;

  /// The frame's body and its title: `publish()`, `pkg in packages`.
  BodyLevel get level => levels.last;

  /// The path to the frame's body: as [levels] open it.
  List<Opened> get path => [for (final level in levels.skip(1)) level.opened!];
}

/// The frames drawn in place in the last of [levels], whose calls go to
/// [functions]: the nodes [expansions] has expanded in its body that it
/// has and that open so, and in their bodies the same way, at any depth.
List<InPlaceFrame> inPlaceFrames(
  List<BodyLevel> levels,
  Map<String, GraphFunction> functions,
  Expansions expansions,
) {
  final path = [for (final level in levels.skip(1)) level.opened!];
  final body = levels.last.body;
  return [
    for (final opened in expansions.at(path))
      if (levelOpened(body, opened, functions) case final level?)
        InPlaceFrame._(body.node(opened.nodeId)!, [
          ...levels,
          level,
        ], inPlaceFrames([...levels, level], functions, expansions)),
  ];
}

/// Every frame of [frames], and those in them, outer first.
Iterable<InPlaceFrame> allFrames(List<InPlaceFrame> frames) sync* {
  for (final frame in frames) {
    yield frame;
    yield* allFrames(frame.frames);
  }
}
