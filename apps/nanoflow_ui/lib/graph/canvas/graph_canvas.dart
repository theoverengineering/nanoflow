import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nanoflow_model/nanoflow_model.dart'
    show CallNode, CopiesNode, GraphBody, GraphFunction, GraphNode;

import '../../layout/layout.dart' as layout;
import '../../state/body_path.dart';
import '../../state/graph_model.dart';
import '../../widgets/clickable.dart';
import 'canvas_marks.dart';
import 'canvas_style.dart';
import 'edges_painter.dart';
import 'exit_labels.dart';
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
  /// узлу, если тот не виден»).
  void revealNode(String id) => _state?._reveal(id);
}

/// What a double click on [node] opens, at [position] on the screen.
typedef OpenNode = void Function(GraphNode node, Offset position);

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
/// A double click on a call or on copies is [onOpenNode]: what it opens
/// (`openings`) is drawn instead.
class GraphCanvas extends StatefulWidget {
  const GraphCanvas({
    super.key,
    required this.model,
    this.controller,
    this.onOpenNode,
    this.topInset = sessionBarRoom,
  });

  /// The room over the graph kept for the session bar floating over the
  /// canvas: fitting keeps nodes out of it.
  static const sessionBarRoom = 60.0;

  final GraphModel model;

  final GraphCanvasController? controller;

  /// Opens a call or copies: on a double click on it.
  final OpenNode? onOpenNode;

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
  final CanvasMarks _marks = CanvasMarks.plain;

  /// The body laid out, and what it is drawn with in JSON: another body
  /// drawn the same keeps the layout and the view.
  GraphBody? _body;
  String? _bodyJson;
  layout.GraphLayout? _layout;

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
    _canvas = widget.model.canvas;
    _layOut(_canvas.body, _canvas.file?.functions ?? const {});
    final graph = _layout;
    _drawing = graph == null ? null : _draw(graph);
  }

  void _layOut(GraphBody? body, Map<String, GraphFunction> functions) {
    // A body read once is drawn with the functions of its own file.
    if (identical(body, _body)) return;
    _body = body;
    // A call is drawn with its function's name and steps, copies with the
    // steps of the functions a copy calls.
    final json = body == null
        ? null
        : jsonEncode([
            body.toJson(),
            for (final node in body.nodes)
              if (node is CallNode || node is CopiesNode)
                [
                  layout.nodeName(node, functions),
                  layout.insideText(node, functions),
                ],
          ]);
    if (json == _bodyJson) return;
    _bodyJson = json;
    _layout = body == null
        ? null
        : layout.layoutBody(body, functions: functions, options: _options);
    _needsFit = true;
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
    final bounds = _layout!.bounds;
    final room = _room(size);
    var scale = 1.0;
    if (bounds.width > 0 && bounds.height > 0) {
      scale = math.min(
        1.0,
        math.min(room.width / bounds.width, room.height / bounds.height),
      );
    }
    _scale = scale.clamp(_minScale, _maxScale);
    _offset = room.center - bounds.center.toOffset() * _scale;
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
    final node = _layout?.nodes[id];
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
                        runId: null,
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
  Widget _view(Widget drawing) => OverflowBox(
    alignment: Alignment.topLeft,
    minWidth: 0,
    minHeight: 0,
    maxWidth: double.infinity,
    maxHeight: double.infinity,
    child: Transform(
      transform: Matrix4.translationValues(_offset.dx, _offset.dy, 0)
        ..scaleByDouble(_scale, _scale, 1, 1),
      child: drawing,
    ),
  );

  /// The arrows, the exits and the nodes of [graph], with the marks; calls
  /// and copies open on a double click.
  Widget _draw(layout.GraphLayout graph) => RepaintBoundary(
    child: SizedBox(
      width: graph.bounds.width,
      height: graph.bounds.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(painter: EdgesPainter(graph, _marks)),
          ),
          Positioned.fill(
            child: CustomPaint(painter: ExitsPainter(graph, _marks)),
          ),
          for (final node in graph.nodes.values)
            Positioned.fromRect(
              rect: NodeTile.areaOf(node),
              child: NodeTile(node: node, onDoubleTap: _opener(node)),
            ),
        ],
      ),
    ),
  );

  /// What a double click on [node] does: opens it, when it opens anything.
  ValueChanged<Offset>? _opener(layout.NodeBox node) {
    final graphNode = node.node;
    final open = widget.onOpenNode;
    if (graphNode == null || open == null) return null;
    final functions = _canvas.file?.functions ?? const {};
    if (openings(graphNode, functions).isEmpty) return null;
    return (position) => open(graphNode, position);
  }
}

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
