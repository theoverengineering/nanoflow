import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nanoflow_model/nanoflow_model.dart'
    show CallNode, CopiesNode, GraphBody, GraphFunction, GraphNode, StepNode;

import '../../layout/layout.dart' as layout;
import '../../state/body_path.dart';
import '../../state/graph_model.dart';
import '../../state/in_place.dart';
import '../../state/session_view.dart';
import '../../widgets/clickable.dart';
import '../copy_switcher.dart';
import 'canvas_marks.dart';
import 'canvas_style.dart';
import 'copies_frame.dart';
import 'edges_painter.dart';
import 'exit_labels.dart';
import 'frame_toggle.dart';
import 'function_frame.dart';
import 'layout_geometry.dart';
import 'legend.dart';
import 'node_tile.dart';

/// Moves the view of a [GraphCanvas] from outside it.
class GraphCanvasController {
  _GraphCanvasState? _state;

  /// The view's zoom: 1 draws the graph at the mockups' size.
  double get scale => _state?._scale ?? 1;

  /// Where the layout's origin is on the canvas.
  Offset get offset => _state?._offset ?? Offset.zero;

  /// Pans the view so that the node [id] is in it, unless it already is
  /// (docs/ui-spec.md «Выбор»: «Шаг в ленте прокручивает холст к своему
  /// узлу, если тот не виден»). A node in a frame drawn in place is named
  /// by the ids of the frames it is in and its own, joined by `/`: `5/2`.
  void revealNode(String id) => _state?._reveal(id);
}

/// What a double click on [node], a node of the body at [path], opens —
/// or what its `+` expands in place —, at [position] on the screen.
typedef OpenNode = void Function(
  List<Opened> path,
  GraphNode node,
  Offset position,
);

/// Opens the step details window on the step node [node] of the body drawn,
/// or of the frame drawn in place at [path].
typedef OpenStep = void Function(StepNode node, List<Opened>? path);

/// The graph canvas (docs/ui-spec.md «Холст», «Граф»; spec §9 «Граф»): one
/// level of the graph of the selected session, or of the current graph
/// (`CanvasGraph.levels`), over a dotted grid that pans and zooms with it.
///
/// A drag or a two-finger trackpad swipe pans, as does the scroll wheel; a
/// pinch, or the wheel with ⌘ or Ctrl, zooms; the buttons in the bottom
/// left corner fit the graph to the canvas and zoom in and out. The graph is
/// fitted when first shown and when another graph replaces it, but not when
/// new data comes for the same graph.
///
/// With a session, its steps are marked on the nodes (spec §9 «Шаги на
/// графе»); a click on a node selects its last step. The body of copies is
/// drawn in their frame, with the copy switcher (decisions 10, 11).
///
/// A double click on a call or on copies is [onOpenNode]: what it opens
/// (`openings`) is drawn instead; on a step, [onOpenStep]. The `+` on a
/// call or copies is [onExpandNode]: the model's expanded nodes are drawn
/// in place, each a frame round its body (decision 6), whose `−` collapses
/// it; in a frame, everything works as on the level drawn, and a copies
/// frame has its switcher and how its copies stand. Expanding or
/// collapsing keeps the node where it is on the screen — or fits the graph
/// again while the view is as fitting left it.
class GraphCanvas extends StatefulWidget {
  const GraphCanvas({
    super.key,
    required this.model,
    this.now = DateTime.now,
    this.controller,
    this.onOpenNode,
    this.onOpenStep,
    this.onExpandNode,
    this.topInset = sessionBarRoom,
  });

  /// The room over the graph kept for the session bar floating over the
  /// canvas: fitting keeps nodes out of it.
  static const sessionBarRoom = 60.0;

  final GraphModel model;

  /// The time to show the selected session at.
  final DateTime Function() now;

  final GraphCanvasController? controller;

  /// Opens a call or copies: on a double click on it.
  final OpenNode? onOpenNode;

  /// Opens the step details window on a step node: on a double click on it.
  final OpenStep? onOpenStep;

  /// Expands a call or copies in place: on its `+`; without it, no `+`.
  final OpenNode? onExpandNode;

  /// The room over the graph that fitting keeps free, for what floats over
  /// the top of the canvas; at most half the canvas. When it changes, the
  /// graph is fitted again, unless the view has been moved.
  final double topInset;

  @override
  State<GraphCanvas> createState() => _GraphCanvasState();
}

class _GraphCanvasState extends State<GraphCanvas> {
  static const _minScale = 0.1;
  static const _maxScale = 4.0;

  /// How much a zoom button zooms.
  static const _zoomStep = 1.25;

  /// How far the scroll wheel must turn, in pixels, to zoom by e.
  static const _wheelZoom = 200.0;

  /// The room fitting keeps free on the sides and at the bottom, where the
  /// zoom buttons and the legend are.
  static const _sideRoom = 24.0;
  static const _bottomRoom = 56.0;

  static const _options = layout.LayoutOptions(measure: measureLabel);

  late CanvasGraph _canvas;
  CanvasMarks _marks = CanvasMarks.plain;

  /// The frame round the body drawn, when it is the body of copies.
  CopiesFrameBox? _frame;

  /// The body laid out, and what it is drawn with in JSON: another body
  /// drawn the same keeps the layout and the view. With the nodes expanded
  /// in it, what the layout was made of.
  GraphBody? _body;
  String? _bodyJson;
  String? _layoutKey;
  layout.GraphLayout? _layout;

  /// The node expanded or collapsed last, by its id on the canvas, and
  /// where its tile's top left corner was on the screen: it stays there.
  ({String id, Offset at})? _anchor;

  /// The graph drawn with its marks, made when they change: moving the view
  /// moves it without building it again.
  Widget? _drawing;

  double _scale = 1;
  Offset _offset = Offset.zero;
  Size _size = Size.zero;

  /// Whether the graph is to be fitted at the next build.
  bool _needsFit = true;

  /// Whether the view is as fitting left it: it fits again when the canvas
  /// changes size.
  bool _fitted = false;

  /// Where the pointer went down or the trackpad was touched: the graph's
  /// point under it follows the gesture from there.
  Offset? _downAt;
  double _gestureScale = 1;
  Offset _gestureAnchor = Offset.zero;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    widget.model.addListener(_changed);
    _read();
  }

  @override
  void didUpdateWidget(GraphCanvas old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._state == this) old.controller!._state = null;
      widget.controller?._state = this;
    }
    if (old.model != widget.model) {
      old.model.removeListener(_changed);
      widget.model.addListener(_changed);
      _read();
    }
    if (old.topInset != widget.topInset && _fitted) _needsFit = true;
  }

  @override
  void dispose() {
    widget.model.removeListener(_changed);
    if (widget.controller?._state == this) widget.controller!._state = null;
    super.dispose();
  }

  void _changed() => setState(_read);

  /// Takes in what the model shows now; lays out a body drawn otherwise.
  void _read() {
    final model = widget.model;
    _canvas = model.canvas;
    final view = _canvas.ofSession ? model.sessionView(widget.now()) : null;
    _layOut(
      _canvas.body,
      _canvas.file?.functions ?? const {},
      _expandedOf(_canvas.frames, view),
    );
    final depth = _canvas.levels.length - 1;
    _marks = CanvasMarks.of(view, depth: depth);
    final graph = _layout;
    final copies = _copiesDrawn();
    final frame = view?.frames.where((f) => f.depth == depth).firstOrNull;
    _frame = graph == null || copies == null
        ? null
        : CopiesFrameBox.around(
            graph.bounds.toRect(),
            title: 'each ${copies.label}',
            count: frame?.countText ?? _plainCount,
            switcher: frame == null ? null : CopySwitcher.widthOf(frame),
          );
    _drawing = graph == null ? null : _draw(graph, copies, frame, view);
  }

  /// What the layout draws in place of [frames]: each one's body, with the
  /// room its frame keeps, and the frames in it.
  Map<String, layout.ExpandedNode> _expandedOf(
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
              count: copies?.countText ?? _plainCount,
              switcher: copies == null ? null : CopySwitcher.widthOf(copies),
              collapsible: true,
            );
          }(),
          _ => FunctionFrameView.roomFor(frame.level.title),
        },
        expanded: _expandedOf(frame.frames, view),
      ),
  };

  /// Across from the title of a frame of copies without a session.
  static const _plainCount = '×n · in parallel';

  /// The copies whose body is drawn; `null` when the body drawn is not
  /// theirs.
  CopiesNode? _copiesDrawn() {
    final levels = _canvas.levels;
    if (levels.length < 2) return null;
    final node = levels[levels.length - 2].body.node(
      levels.last.opened!.nodeId,
    );
    return node is CopiesNode ? node : null;
  }

  /// What is drawn, in the coordinates of the layout: the layout, and the
  /// frame of copies round it.
  Rect get _extent => _frame?.extent ?? _layout!.bounds.toRect();

  void _layOut(
    GraphBody? body,
    Map<String, GraphFunction> functions,
    Map<String, layout.ExpandedNode> expanded,
  ) {
    // A body read once is drawn with the functions of its own file.
    var another = false;
    if (!identical(body, _body)) {
      _body = body;
      final json = body == null ? null : jsonEncode(_keyOf(body, functions));
      if (json != _bodyJson) {
        _bodyJson = json;
        // Another graph: fitted anew, whatever was expanded.
        another = true;
        _needsFit = true;
        _anchor = null;
      }
    }
    final key = expanded.isEmpty
        ? _bodyJson
        : jsonEncode([_bodyJson, _expandedKey(expanded, functions)]);
    if (!another && key == _layoutKey) return;
    final before = _layout;
    _layoutKey = key;
    _layout = body == null
        ? null
        : layout.layoutBody(
            body,
            functions: functions,
            options: _options,
            expanded: expanded,
          );
    // The graph drawn otherwise — nodes expanded or collapsed, a frame's
    // room grown — fits again while the view is as fitting left it; else a
    // node expanded or collapsed stays where it was on the screen.
    final anchor = _anchor;
    _anchor = null;
    if (before == null || _needsFit) return;
    if (_fitted) {
      _needsFit = true;
      return;
    }
    if (anchor == null) return;
    final moved = _boxOf(anchor.id);
    if (moved != null) {
      _offset = anchor.at - moved.tile.toRect().topLeft * _scale;
    }
  }

  /// [body] as it is drawn: a call with its function's name and steps,
  /// copies with the steps of the functions a copy calls.
  static List<Object?> _keyOf(
    GraphBody body,
    Map<String, GraphFunction> functions,
  ) => [
    body.toJson(),
    for (final node in body.nodes)
      if (node is CallNode || node is CopiesNode)
        [layout.nodeName(node, functions), layout.insideText(node, functions)],
  ];

  /// [expanded] as the layout draws it.
  static List<Object?> _expandedKey(
    Map<String, layout.ExpandedNode> expanded,
    Map<String, GraphFunction> functions,
  ) => [
    for (final MapEntry(key: id, value: node) in expanded.entries)
      [
        id,
        _keyOf(node.body, functions),
        [
          node.room.top,
          node.room.side,
          node.room.bottom,
          node.room.width,
          node.room.above,
        ],
        _expandedKey(node.expanded, functions),
      ],
  ];

  /// The node [id] on the canvas: of the body drawn, or of a frame drawn in
  /// place in it (`5/2`); the deepest of the path there is.
  layout.NodeBox? _boxOf(String id) {
    layout.NodeBox? box;
    var nodes = _layout?.nodes;
    for (final part in id.split('/')) {
      final next = nodes?[part];
      if (next == null) break;
      box = next;
      nodes = next.frame?.inner.nodes;
    }
    return box;
  }

  /// Keeps the node [id] where it is on the screen once its frame or tile
  /// takes its place.
  void _anchorAt(String id) {
    final box = _boxOf(id);
    if (box == null) return;
    _anchor = (id: id, at: _offset + box.tile.toRect().topLeft * _scale);
  }

  /// Where fitting and revealing put the graph: the canvas less the room
  /// for what floats over it.
  Rect _room(Size size) => Rect.fromLTRB(
    _sideRoom,
    math.min(widget.topInset, size.height / 2),
    size.width - _sideRoom,
    size.height - _bottomRoom,
  );

  /// Makes the whole graph fit [size], centred, no bigger than drawn.
  void _fitTo(Size size) {
    final bounds = _extent;
    final room = _room(size);
    var scale = 1.0;
    if (bounds.width > 0 && bounds.height > 0) {
      scale = math.min(
        1.0,
        math.min(room.width / bounds.width, room.height / bounds.height),
      );
    }
    _scale = scale.clamp(_minScale, _maxScale);
    _offset = room.center - bounds.center * _scale;
    _needsFit = false;
    _fitted = true;
  }

  void _fit() => setState(() => _fitTo(_size));

  /// Zooms by [factor], keeping the graph's point at [focus] where it is.
  void _zoomAt(Offset focus, double factor) {
    final scale = (_scale * factor).clamp(_minScale, _maxScale);
    _offset = focus - (focus - _offset) / _scale * scale;
    _scale = scale;
    _fitted = false;
  }

  void _zoom(double factor) =>
      setState(() => _zoomAt(_room(_size).center, factor));

  void _reveal(String id) {
    final node = _boxOf(id);
    if (node == null || _size.isEmpty) return;
    final area = node.tile
        .toRect()
        .expandToInclude(node.nameRect.toRect())
        .expandToInclude(node.placeRect.toRect());
    final shown = Rect.fromLTRB(
      area.left * _scale + _offset.dx,
      area.top * _scale + _offset.dy,
      area.right * _scale + _offset.dx,
      area.bottom * _scale + _offset.dy,
    );
    final room = _room(_size);
    if (room.intersect(shown) == shown) return;
    setState(() {
      _offset += room.center - shown.center;
      _fitted = false;
    });
  }

  void _gestureStarted(ScaleStartDetails details) {
    final at = details.pointerCount > 1
        ? details.localFocalPoint
        : _downAt ?? details.localFocalPoint;
    _gestureScale = _scale;
    _gestureAnchor = (at - _offset) / _scale;
  }

  void _gestureMoved(ScaleUpdateDetails details) => setState(() {
    _scale = (_gestureScale * details.scale).clamp(_minScale, _maxScale);
    _offset = details.localFocalPoint - _gestureAnchor * _scale;
    _fitted = false;
  });

  void _scrolled(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _layout == null) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scroll = event as PointerScrollEvent;
      final keys = HardwareKeyboard.instance;
      setState(() {
        if (keys.isMetaPressed || keys.isControlPressed) {
          _zoomAt(
            scroll.localPosition,
            math.exp(-scroll.scrollDelta.dy / _wheelZoom),
          );
        } else {
          _offset -= scroll.scrollDelta;
          _fitted = false;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      if (_layout != null &&
          !size.isEmpty &&
          (_needsFit || _fitted && size != _size)) {
        _fitTo(size);
      }
      _size = size;
      final graph = _layout;
      final drawing = _drawing;
      return ColoredBox(
        color: CanvasColors.background,
        child: Listener(
          onPointerDown: (event) => _downAt = event.localPosition,
          onPointerPanZoomStart: (event) => _downAt = event.localPosition,
          onPointerSignal: _scrolled,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _gestureStarted,
            onScaleUpdate: _gestureMoved,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _GridPainter(_scale, _offset)),
                ),
                if (drawing != null)
                  Positioned.fill(child: ClipRect(child: _view(drawing))),
                if (_canvas.placeholder case final text?)
                  Positioned.fill(
                    child: Center(
                      child: Text(
                        text,
                        style: CanvasText.placeholder,
                        textScaler: TextScaler.noScaling,
                      ),
                    ),
                  ),
                if (graph != null) ...[
                  Positioned(
                    left: 16,
                    bottom: 14,
                    child: _ZoomButtons(
                      onFit: _fit,
                      onZoomIn: () => _zoom(_zoomStep),
                      onZoomOut: () => _zoom(1 / _zoomStep),
                    ),
                  ),
                  // For Current graph only the zoom buttons remain
                  // (ui-spec «Холст»).
                  if (_canvas.ofSession)
                    Positioned(
                      right: 16,
                      bottom: 14,
                      child: Legend(
                        backEdges: _marks.backEdges(
                          graph.edges.where((edge) => edge.isDashed),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  /// [drawing] moved and scaled to the view.
  Widget _view(Widget drawing) {
    final at = _offset + _extent.topLeft * _scale;
    return OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: 0,
      minHeight: 0,
      maxWidth: double.infinity,
      maxHeight: double.infinity,
      child: Transform(
        transform: Matrix4.translationValues(at.dx, at.dy, 0)
          ..scaleByDouble(_scale, _scale, 1, 1),
        child: drawing,
      ),
    );
  }

  /// The arrows, the exits and the nodes of [graph], with the marks, in
  /// the frame of [copies] when it is their body that is drawn, [frame] the
  /// session's copies of it; calls and copies open on a double click,
  /// steps their details. The nodes expanded in place are frames, the
  /// bodies in them drawn the same way, [view] the session's.
  Widget _draw(
    layout.GraphLayout graph,
    CopiesNode? copies,
    CopiesFrame? frame,
    SessionView? view,
  ) {
    final extent = _extent;
    final box = _frame;
    final layers = (frames: <Widget>[], lines: <Widget>[], tiles: <Widget>[]);
    _drawBody(
      graph,
      _marks,
      layers,
      path: null,
      ids: const [],
      frames: _canvas.frames,
      view: view,
    );
    return RepaintBoundary(
      child: SizedBox(
        width: extent.width,
        height: extent.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (box != null && copies != null)
              Positioned.fill(
                child: CopiesFrameView(
                  box: box,
                  title: 'each ${copies.label}',
                  count: frame?.countText ?? _plainCount,
                  footer: frame?.footer,
                  switcher: frame == null
                      ? null
                      : CopySwitcher(
                          frame: frame,
                          hintOf: widget.model.hintOf,
                          onSelect: (id) =>
                              widget.model.selectCopy(frame.depth, id),
                        ),
                ),
              ),
            Positioned(
              left: -extent.left,
              top: -extent.top,
              width: graph.bounds.width,
              height: graph.bounds.height,
              // Frames under the arrows, the arrows under the tiles: the
              // painters let clicks through to the frames' buttons.
              child: Stack(
                clipBehavior: Clip.none,
                children: [...layers.frames, ...layers.lines, ...layers.tiles],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Draws [graph], the layout of the body drawn — or, at [path], of the
  /// body of a frame drawn in place —, with [marks]: its arrows and exits
  /// in [layers]' lines, its nodes in its tiles; [frames], the nodes
  /// expanded in it, are frames in [layers]' frames, their bodies drawn in
  /// turn. The ids on the canvas of its nodes start with [ids].
  void _drawBody(
    layout.GraphLayout graph,
    CanvasMarks marks,
    _Layers layers, {
    required List<Opened>? path,
    required List<String> ids,
    required List<InPlaceFrame> frames,
    required SessionView? view,
  }) {
    final bodyPath = path ?? _canvas.path;
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
              _anchorAt(id);
              widget.model.collapseNode(bodyPath, node.id);
            },
          ),
        );
        _drawBody(
          box.inner,
          CanvasMarks.ofFrame(scope),
          layers,
          path: frame.path,
          ids: [...ids, node.id],
          frames: frame.frames,
          view: view,
        );
        continue;
      }
      layers.tiles.add(
        Positioned.fromRect(
          rect: NodeTile.areaOf(node),
          child: NodeTile(
            node: node,
            id: id,
            marks: marks.node(node.id),
            selected: marks.selected(node.id),
            allCopies: marks.allCopies,
            copies: marks.copies(node.id),
            onTap: marks.isPlain || node.node == null
                ? null
                : () => widget.model.clickNode(node.id, path: path),
            onDoubleTap: _opener(node, path),
            onExpand: _expander(node, bodyPath, id),
          ),
        ),
      );
    }
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
        count: copies?.countText ?? _plainCount,
        footer: copies?.footer,
        onCollapse: collapse,
        collapseKey: key,
        switcher: copies == null
            ? null
            : CopySwitcher(
                frame: copies,
                hintOf: widget.model.hintOf,
                onSelect: (copyId) =>
                    widget.model.selectCopyAt(frame.path, copyId),
              ),
      ),
    );
  }

  /// What a double click on [node] of the body drawn — or of the frame
  /// drawn in place at [path] — does: opens a call or copies, when it opens
  /// anything; the details of a step.
  ValueChanged<Offset>? _opener(layout.NodeBox node, List<Opened>? path) {
    final graphNode = node.node;
    if (graphNode is StepNode) {
      final open = widget.onOpenStep;
      return open == null ? null : (_) => open(graphNode, path);
    }
    final open = widget.onOpenNode;
    if (graphNode == null || open == null) return null;
    final functions = _canvas.file?.functions ?? const {};
    if (openings(graphNode, functions).isEmpty) return null;
    return (position) => open(path ?? _canvas.path, graphNode, position);
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
    final expand = widget.onExpandNode;
    if (graphNode == null || expand == null) return null;
    final functions = _canvas.file?.functions ?? const {};
    if (openings(graphNode, functions).isEmpty) return null;
    return (position) {
      _anchorAt(id);
      expand(path, graphNode, position);
    };
  }
}

/// What the canvas draws, bottom to top: the frames drawn in place, the
/// arrows and exits, the tiles.
typedef _Layers = ({
  List<Widget> frames,
  List<Widget> lines,
  List<Widget> tiles,
});

/// The canvas's dots, 22 px apart at full size, moving with the graph.
/// Zoomed far out, every other one is left out, and so on.
class _GridPainter extends CustomPainter {
  _GridPainter(this.scale, this.offset);

  final double scale;
  final Offset offset;

  static const _cell = 22.0;
  static const _minStep = 11.0;

  @override
  void paint(Canvas canvas, Size size) {
    var step = _cell * scale;
    while (step < _minStep) {
      step *= 2;
    }
    // A dot in the middle of each cell, as the mockups' CSS grid has them.
    final left = (offset.dx + _cell / 2 * scale) % step;
    final top = (offset.dy + _cell / 2 * scale) % step;
    final dots = [
      for (var x = left; x < size.width; x += step)
        for (var y = top; y < size.height; y += step) Offset(x, y),
    ];
    canvas.drawPoints(
      PointMode.points,
      dots,
      Paint()
        ..color = CanvasColors.gridDot
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.scale != scale || old.offset != offset;
}

/// Fit, zoom in, zoom out: the bottom left corner of the canvas.
class _ZoomButtons extends StatelessWidget {
  const _ZoomButtons({
    required this.onFit,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final VoidCallback onFit;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 6,
    children: [
      _button('Zoom to fit', _ZoomIcon.fit, onFit),
      _button('Zoom in', _ZoomIcon.zoomIn, onZoomIn),
      _button('Zoom out', _ZoomIcon.zoomOut, onZoomOut),
    ],
  );

  static Widget _button(String name, _ZoomIcon icon, VoidCallback onTap) =>
      Tooltip(
        message: name,
        child: Clickable(
          onTap: onTap,
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CanvasColors.panel,
              border: Border.all(color: CanvasColors.buttonBorder),
              borderRadius: const BorderRadius.all(Radius.circular(7)),
            ),
            child: CustomPaint(
              size: const Size.square(15),
              painter: _ZoomIconPainter(icon),
            ),
          ),
        ),
      );
}

enum _ZoomIcon { fit, zoomIn, zoomOut }

/// The zoom buttons' icons: the mockups' SVG, 16 units.
class _ZoomIconPainter extends CustomPainter {
  _ZoomIconPainter(this.icon);

  final _ZoomIcon icon;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 16);
    final stroke = Paint()
      ..color = CanvasColors.buttonIcon
      ..style = PaintingStyle.stroke
      ..strokeWidth = icon == _ZoomIcon.fit ? 1.4 : 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    switch (icon) {
      case _ZoomIcon.fit:
        for (final (a, b, c) in const [
          (Offset(2, 5.5), Offset(2, 2), Offset(5.5, 2)),
          (Offset(10.5, 2), Offset(14, 2), Offset(14, 5.5)),
          (Offset(14, 10.5), Offset(14, 14), Offset(10.5, 14)),
          (Offset(5.5, 14), Offset(2, 14), Offset(2, 10.5)),
        ]) {
          path
            ..moveTo(a.dx, a.dy)
            ..lineTo(b.dx, b.dy)
            ..lineTo(c.dx, c.dy);
        }
      case _ZoomIcon.zoomIn:
        path
          ..moveTo(8, 3.5)
          ..lineTo(8, 12.5)
          ..moveTo(3.5, 8)
          ..lineTo(12.5, 8);
      case _ZoomIcon.zoomOut:
        path
          ..moveTo(3.5, 8)
          ..lineTo(12.5, 8);
    }
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_ZoomIconPainter old) => old.icon != icon;
}
