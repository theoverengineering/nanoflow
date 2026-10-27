// The bodies the canvas draws: the level drawn, and the bodies of the calls
// and copies expanded in place in it (decision 6), each in its frame, at
// any depth — what the layout is given for them, and how they are drawn.

import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:nanoflow_model/nanoflow_model.dart'
    show CallNode, CopiesNode, GraphBody, GraphFunction, GraphNode, EffectNode;

import '../../layout/layout.dart' as layout;
import '../../state/body_path.dart';
import '../../state/graph_model.dart';
import '../../state/in_place.dart';
import '../../state/session_view.dart';
import '../../widgets/doc_text.dart';
import '../copy_switcher.dart';
import 'canvas_marks.dart';
import 'copies_frame.dart';
import 'edges_painter.dart';
import 'exit_labels.dart';
import 'frame_toggle.dart';
import 'function_frame.dart';
import 'layout_geometry.dart';
import 'node_tile.dart';

/// What a double click on [node], a node of the body at [path], opens, at
/// [position] on the screen; or its ↗, opening its function as the main
/// graph.
typedef OpenNode = void Function(
  List<Opened> path,
  GraphNode node,
  Offset position,
);

/// Expands [node], a node of the body at [path], in place, from [position]
/// on the screen; whether it did — the function of a call of several may
/// not be chosen.
typedef ExpandNode = Future<bool> Function(
  List<Opened> path,
  GraphNode node,
  Offset position,
);

/// Opens the effect details window on the effect node [node] of the body drawn,
/// or of the frame drawn in place at [path].
typedef OpenEffect = void Function(EffectNode node, List<Opened>? path);

/// Across from the title of a frame of copies without a session.
const plainCopiesCount = '×n · in parallel';

/// What the layout draws in place of [frames]: each one's body, with the
/// room its frame keeps — for copies, with [view]'s switcher —, and the
/// frames in it.
Map<String, layout.ExpandedNode> expandedOf(
  List<InPlaceFrame> frames,
  SessionView? view,
) => {
  for (final frame in frames)
    frame.nodeId: layout.ExpandedNode(
      frame.level.body,
      room: switch (frame.node) {
        CopiesNode(:final label) => () {
          final copies = view?.scopeOf(frame.path)?.copies;
          return CopiesFrameBox.roomFor(
            title: 'each $label',
            count: copies?.countText ?? plainCopiesCount,
            switcher: copies == null ? null : CopySwitcher.widthOf(copies),
            collapsible: true,
          );
        }(),
        _ => FunctionFrameView.roomFor(frame.level.title),
      },
      expanded: expandedOf(frame.frames, view),
    ),
};

/// [body] as it is drawn, in JSON: a call with its function's name and
/// effects, copies with the effects of the functions a copy calls. Another body
/// drawn the same keeps its layout and the view.
String bodyKeyOf(GraphBody body, Map<String, GraphFunction> functions) =>
    jsonEncode([
      body.toJson(),
      for (final node in body.nodes)
        if (node is CallNode || node is CopiesNode)
          [
            layout.nodeName(node, functions),
            layout.insideText(node, functions),
          ],
    ]);

/// Which nodes [frames] expand, as a key: other nodes, another key.
String expansionsKeyOf(List<InPlaceFrame> frames) =>
    [for (final frame in allFrames(frames)) levelKey(frame.path)].join('|');

/// Whether [a] and [b] are laid out the same: the very same bodies, with
/// the same rooms, at the same ids, and so on in them.
bool sameExpanded(
  Map<String, layout.ExpandedNode> a,
  Map<String, layout.ExpandedNode> b,
) {
  if (a.length != b.length) return false;
  for (final MapEntry(key: id, value: x) in a.entries) {
    final y = b[id];
    if (y == null ||
        !identical(x.body, y.body) ||
        x.room != y.room ||
        !sameExpanded(x.expanded, y.expanded)) {
      return false;
    }
  }
  return true;
}

/// Draws the bodies of the canvas of [model], its [canvas] graph, into
/// [layers]: the body drawn, and in each frame drawn in place the body of
/// its call or copies, with what [view] shows of the session on them. A
/// node in a frame works as one on the level drawn — a click, a double
/// click ([onOpenNode], [onOpenEffect]), its `+` ([onExpandNode]), a call's
/// ↗ ([onOpenAsGraph]), its place ([onOpenPlace]) — and its id on the canvas
/// is the path of ids to it, `5/2`.
///
/// A node about to be expanded or collapsed is [anchor]ed, so that it stays
/// where it is on the screen; [unanchor] lets go of it when it is not.
final class BodyDrawer {
  BodyDrawer({
    required this.model,
    required this.canvas,
    required this.view,
    required this.anchor,
    required this.unanchor,
    this.onOpenNode,
    this.onOpenEffect,
    this.onExpandNode,
    this.onOpenAsGraph,
    this.onOpenPlace,
  });

  final GraphModel model;
  final CanvasGraph canvas;
  final SessionView? view;
  final ValueChanged<String> anchor;
  final VoidCallback unanchor;
  final OpenNode? onOpenNode;
  final OpenEffect? onOpenEffect;
  final ExpandNode? onExpandNode;
  final OpenNode? onOpenAsGraph;
  final ValueChanged<String>? onOpenPlace;

  /// What is drawn, bottom to top: the frames drawn in place, the ring of
  /// the selected effect's node, the arrows and exits, the tiles. The
  /// painters let clicks through to the frames' buttons.
  final layers = (
    frames: <Widget>[],
    rings: <Widget>[],
    lines: <Widget>[],
    tiles: <Widget>[],
  );

  /// Draws [graph], the layout of the body drawn — or, at [path], of the
  /// body of a frame drawn in place —, with [marks]: its arrows and exits
  /// in the lines, its nodes in the tiles but the ports of a frame; the
  /// nodes [frames] expand in it are frames, their bodies drawn in turn.
  /// The ids on the canvas of its nodes start with [ids].
  void draw(
    layout.GraphLayout graph,
    CanvasMarks marks, {
    List<Opened>? path,
    List<String> ids = const [],
    required List<InPlaceFrame> frames,
  }) {
    final bodyPath = path ?? canvas.path;
    layers.lines
      ..add(
        Positioned.fill(
          child: CustomPaint(painter: EdgesPainter(graph, marks)),
        ),
      )
      ..add(
        Positioned.fill(
          child: CustomPaint(painter: ExitsPainter(graph, marks)),
        ),
      );
    for (final node in graph.nodes.values) {
      if (node.port) continue;
      final id = [...ids, node.id].join('/');
      final box = node.frame;
      final frame = frames.where((f) => f.nodeId == node.id).firstOrNull;
      if (box != null && frame != null) {
        final scope = view?.scopeOf(frame.path);
        layers.frames.add(
          _frameOf(
            node,
            frame,
            scope,
            id: id,
            collapse: () {
              anchor(id);
              model.collapseNode(bodyPath, node.id);
            },
          ),
        );
        draw(
          box.inner,
          CanvasMarks.ofFrame(scope),
          path: frame.path,
          ids: [...ids, node.id],
          frames: frame.frames,
        );
        continue;
      }
      if (marks.selected(node.id)) layers.rings.add(NodeTile.ringOf(node, id));
      layers.tiles.add(
        Positioned.fromRect(
          rect: NodeTile.areaOf(node),
          child: NodeTile(
            node: node,
            id: id,
            marks: marks.node(node.id),
            allCopies: marks.allCopies,
            copies: marks.copies(node.id),
            onTap: marks.isPlain || node.node == null
                ? null
                : () => model.clickNode(node.id, path: path),
            onDoubleTap: _opener(node, path),
            onExpand: _expander(node, bodyPath, id),
            onOpenAsGraph: _graphOpener(node, bodyPath),
            onOpenPlace: _placeOpener(node),
            doc: _docOf(node.node),
          ),
        ),
      );
    }
  }

  /// What the tile of [node] says in its tooltip (node docs design §4.2):
  /// an effect's doc, the docs of the functions a call goes to; nothing for
  /// any other node.
  InlineSpan? _docOf(GraphNode? node) {
    final functions = canvas.file?.functions ?? const {};
    return switch (node) {
      EffectNode(:final doc?) => docSpan(doc),
      CallNode(functions: final ids) => functionDocsSpan([
        for (final id in ids)
          (title: functionTitle(id), doc: functions[id]?.doc),
      ]),
      _ => null,
    };
  }

  /// The frame of the node [node] expanded in place, [frame], with what
  /// the session shows in it, [scope]: a call's outline and title, or the
  /// copies' stack with their switcher; its `−` [collapse]s it.
  Widget _frameOf(
    layout.NodeBox node,
    InPlaceFrame frame,
    FrameScope? scope, {
    required String id,
    required VoidCallback collapse,
  }) {
    final rect = node.tile.toRect();
    final key = FrameToggle.collapseKeyOf(id);
    final copiesNode = frame.node;
    if (copiesNode is! CopiesNode) {
      return Positioned.fromRect(
        rect: rect,
        child: FunctionFrameView(
          title: frame.level.title,
          doc: switch (frame.level.doc) {
            final doc? => docSpan(doc),
            null => null,
          },
          onCollapse: collapse,
          collapseKey: key,
        ),
      );
    }
    final copies = scope?.copies;
    final box = CopiesFrameBox.at(rect, switcher: copies != null);
    return Positioned.fromRect(
      rect: box.extent,
      child: CopiesFrameView(
        box: box,
        title: 'each ${copiesNode.label}',
        count: copies?.countText ?? plainCopiesCount,
        footer: copies?.footer,
        onCollapse: collapse,
        collapseKey: key,
        switcher: copies == null
            ? null
            : CopySwitcher(
                frame: copies,
                hintOf: model.hintOf,
                onSelect: (copyId) => model.selectCopyAt(frame.path, copyId),
              ),
      ),
    );
  }

  /// What a double click on [node] of the body drawn — or of the frame
  /// drawn in place at [path] — does: opens a call or copies, when it opens
  /// anything; the details of an effect.
  ValueChanged<Offset>? _opener(layout.NodeBox node, List<Opened>? path) {
    final graphNode = node.node;
    if (graphNode is EffectNode) {
      final open = onOpenEffect;
      return open == null ? null : (_) => open(graphNode, path);
    }
    final open = onOpenNode;
    if (graphNode == null || open == null) return null;
    final functions = canvas.file?.functions ?? const {};
    if (openings(graphNode, functions).isEmpty) return null;
    return (position) => open(path ?? canvas.path, graphNode, position);
  }

  /// What the `+` of [node], a node of the body at [path] with the id [id]
  /// on the canvas, does: expands a call or copies in place, when it opens
  /// anything; none for any other node.
  ValueChanged<Offset>? _expander(
    layout.NodeBox node,
    List<Opened> path,
    String id,
  ) {
    final graphNode = node.node;
    final expand = onExpandNode;
    if (graphNode == null || expand == null) return null;
    final functions = canvas.file?.functions ?? const {};
    if (openings(graphNode, functions).isEmpty) return null;
    return (position) async {
      anchor(id);
      if (!await expand(path, graphNode, position)) unanchor();
    };
  }

  /// What the ↗ of [node], a node of the body at [path], does: opens the
  /// function of a call as the main graph, when the graph file has one of
  /// its functions (`GraphModel.graphOpenings`) — a session's snapshot may
  /// call one renamed since; none for any other node (open-as-graph design
  /// §2).
  ValueChanged<Offset>? _graphOpener(layout.NodeBox node, List<Opened> path) {
    final graphNode = node.node;
    final open = onOpenAsGraph;
    if (graphNode == null || open == null) return null;
    if (model.graphOpenings(graphNode).isEmpty) return null;
    return (position) => open(path, graphNode, position);
  }

  /// What the place under [node]'s tile does: opens it in the editor; none
  /// for a node without a place.
  VoidCallback? _placeOpener(layout.NodeBox node) {
    final place = node.node?.place;
    final open = onOpenPlace;
    return place == null || open == null ? null : () => open(place);
  }
}
