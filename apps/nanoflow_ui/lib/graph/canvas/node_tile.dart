import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../layout/layout.dart' as layout;
import '../../layout/layout.dart' show LabelKind;
import '../../state/graph_marks.dart';
import '../../state/runs.dart';
import 'canvas_style.dart';
import 'layout_geometry.dart';

/// A node on the canvas (docs/ui-spec.md «Граф»): the square tile with its
/// icon, framed in the node's state, with the state's badge on its corner;
/// the name and the command under it, `START` over a start node; the runs on
/// the node and its visit count over its top right corner; the accent ring
/// of the selected step's node.
///
/// The canvas places it at [areaOf] the node; of all that, only the tile is
/// clicked. A click is [onTap], a double click [onDoubleTap].
class NodeTile extends StatelessWidget {
  NodeTile({
    required this.node,
    required this.state,
    this.selected = false,
    this.markers = const [],
    this.visits,
    this.selectedRun,
    this.onTap,
    this.onDoubleTap,
  }) : super(key: keyOf(node.name));

  /// The key of the widget of the node [name].
  static Key keyOf(String name) => ValueKey(('node', name));

  /// The key of the tile itself of the node [name]: what is clicked.
  static Key tileKeyOf(String name) => ValueKey(('tile', name));

  final layout.NodeBox node;

  /// `null` for `Current graph`: the tile has no state.
  final NodeState? state;

  /// Whether the selected step is on the node: the ring, the name bold.
  final bool selected;

  /// The runs on the node, in the order they were created.
  final List<RunMarker> markers;

  /// `2×` for a node entered more than once.
  final String? visits;

  /// The selected run: its marker stays when the markers do not fit.
  final String? selectedRun;

  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  /// How far round the tile the widget reaches: the ring, the badges.
  static const _margin = 16.0;

  /// The canvas area a node's widget takes: its tile with what is drawn
  /// round it, its texts.
  static Rect areaOf(layout.NodeBox node) {
    var area = node.tile.toRect().inflate(_margin);
    for (final rect in [node.nameRect, node.commandRect, ?node.startRect]) {
      area = area.expandToInclude(rect.toRect());
    }
    return area;
  }

  @override
  Widget build(BuildContext context) {
    final area = areaOf(node);
    Rect local(layout.Rect rect) => rect.toRect().shift(-area.topLeft);
    final tile = local(node.tile);
    final look = _Look.of(state);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _clickable(tile, look),
        if (node.startRect case final start?)
          _text(
            local(start),
            layout.startCaption,
            CanvasText.startCaption,
            align: TextAlign.left,
          ),
        _text(
          local(node.nameRect),
          node.name,
          CanvasText.name.copyWith(
            color: look.name,
            fontWeight: selected ? FontWeight.w700 : look.nameWeight,
          ),
        ),
        _text(
          local(node.commandRect),
          node.command,
          CanvasText.command.copyWith(color: look.command),
        ),
        if (markers.isNotEmpty || visits != null)
          Positioned(
            right: area.width - tile.right - _overhang,
            top: tile.top - 9,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: _badgeGap,
              children: _badges(tile.width + 2 * _overhang),
            ),
          ),
      ],
    );
  }

  static const _radius = 12.0;
  static const _ring = 4.0;

  /// How far past the tile's sides the badges over it may reach.
  static const _overhang = 6.0;
  static const _badgeGap = 4.0;

  /// The badges over the tile: the runs on the node and the visit count.
  /// When they are wider than [room], the runs collapse into one: the
  /// selected run if it is on the node, else the first, with how many more
  /// there are (`c3d4 +2`) and every id in its tooltip.
  List<Widget> _badges(double room) {
    final count = visits;
    var width = count == null ? 0.0 : _CountBadge.widthOf(count);
    for (final marker in markers) {
      if (width > 0) width += _badgeGap;
      width += _RunBadge.widthOf(marker.shortId, marker.phase);
    }
    final List<Widget> runs;
    if (width <= room || markers.length < 2) {
      runs = [
        for (final marker in markers)
          _RunBadge(marker.phase, marker.shortId, marker.runId),
      ];
    } else {
      final shown =
          markers.where((marker) => marker.runId == selectedRun).firstOrNull ??
          markers.first;
      runs = [
        _RunBadge(
          shown.phase,
          '${shown.shortId} +${markers.length - 1}',
          [for (final marker in markers) marker.runId].join('\n'),
        ),
      ];
    }
    return [...runs, if (count != null) _CountBadge(count)];
  }

  /// The tile with the state badge on its corner: what is clicked, under the
  /// pointing hand. Only the two shapes are hit, not the box round them.
  Widget _clickable(Rect tile, _Look look) {
    final badge = _badge(state);
    // The badge's box, 21 px with its ring, 10 px into the tile's corner.
    final badgeBox = Rect.fromLTWH(tile.right - 10, tile.bottom - 10, 21, 21);
    final region = badge == null ? tile : tile.expandToInclude(badgeBox);
    return Positioned.fromRect(
      rect: region,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        hitTestBehavior: HitTestBehavior.deferToChild,
        child: RawGestureDetector(
          gestures: {
            SerialTapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  SerialTapGestureRecognizer
                >(
                  SerialTapGestureRecognizer.new,
                  (recognizer) => recognizer.onSerialTapUp = _tapped,
                ),
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fromRect(
                rect: tile.shift(-region.topLeft),
                child: _tile(look),
              ),
              if (badge != null)
                Positioned(
                  left: badgeBox.left - region.left,
                  top: badgeBox.top - region.top,
                  child: badge,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(_Look look) => DecoratedBox(
    key: tileKeyOf(node.name),
    decoration: BoxDecoration(
      color: look.fill,
      border: Border.all(color: look.border, width: look.borderWidth),
      borderRadius: const BorderRadius.all(Radius.circular(_radius)),
      boxShadow: [
        if (selected)
          const BoxShadow(color: CanvasColors.ring, spreadRadius: _ring),
      ],
    ),
    child: Center(
      child: CustomPaint(
        size: const Size.square(28),
        painter: _IconPainter(fork: node.isFork, color: look.icon),
      ),
    ),
  );

  void _tapped(SerialTapUpDetails details) {
    switch (details.count) {
      case 1:
        onTap?.call();
      case 2:
        onDoubleTap?.call();
    }
  }

  /// [text] centred on [rect] in [style], or from its left.
  static Widget _text(
    Rect rect,
    String text,
    TextStyle style, {
    TextAlign align = TextAlign.center,
  }) {
    final height = style.fontSize! * style.height!;
    // Room on both sides, so a text a hair wider than measured still fits.
    const slack = 20.0;
    return Positioned(
      left: align == TextAlign.center ? rect.left - slack : rect.left,
      top: rect.top + (rect.height - height) / 2,
      width: rect.width + 2 * slack,
      child: Text(
        text,
        style: style,
        textAlign: align,
        textScaler: TextScaler.noScaling,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
      ),
    );
  }

  static Widget? _badge(NodeState? state) => switch (state) {
    NodeState.visited => const _StateBadge(
      fill: Color(0xFF2A9D61),
      failed: false,
    ),
    NodeState.failed => const _StateBadge(
      fill: Color(0xFFD9434A),
      failed: true,
    ),
    NodeState.running => const _Spinner(),
    NodeState.notVisited || null => null,
  };
}

/// The colors of a tile and its texts in a node state.
final class _Look {
  const _Look({
    required this.fill,
    required this.border,
    required this.borderWidth,
    required this.icon,
    required this.name,
    required this.nameWeight,
    required this.command,
  });

  final Color fill;
  final Color border;
  final double borderWidth;
  final Color icon;
  final Color name;
  final FontWeight nameWeight;
  final Color command;

  static _Look of(NodeState? state) => switch (state) {
    null => plain,
    NodeState.notVisited => notVisited,
    NodeState.visited => visited,
    NodeState.running => running,
    NodeState.failed => failed,
  };

  /// `Current graph`: no state.
  static const plain = _Look(
    fill: Color(0xFF323338),
    border: Color(0xFF55565C),
    borderWidth: 1.5,
    icon: Color(0xFFC9CACF),
    name: Color(0xFFECECEE),
    nameWeight: FontWeight.w600,
    command: Color(0xFF9A9BA2),
  );

  static const notVisited = _Look(
    fill: Color(0xFF2C2D32),
    border: Color(0xFF45464C),
    borderWidth: 1.5,
    icon: Color(0xFF6E6F76),
    name: Color(0xFF9A9BA2),
    nameWeight: FontWeight.w500,
    command: Color(0xFF8A8B92),
  );

  static const visited = _Look(
    fill: Color(0xFF323338),
    border: Color(0xFF3CC47C),
    borderWidth: 2,
    icon: Color(0xFFC9CACF),
    name: Color(0xFFECECEE),
    nameWeight: FontWeight.w600,
    command: Color(0xFF9A9BA2),
  );

  static const running = _Look(
    fill: Color(0xFF36302A),
    border: Color(0xFFF2A93B),
    borderWidth: 2,
    icon: Color(0xFFF2A93B),
    name: Color(0xFFF7F3EA),
    nameWeight: FontWeight.w600,
    command: Color(0xFFC9A36A),
  );

  static const failed = _Look(
    fill: Color(0xFF382A2C),
    border: Color(0xFFF0555C),
    borderWidth: 2,
    icon: Color(0xFFF0555C),
    name: Color(0xFFF7ECEC),
    nameWeight: FontWeight.w600,
    command: Color(0xFFC98A8D),
  );
}

/// A worker's terminal or a fork's fork: the mockups' SVG, 28 units.
class _IconPainter extends CustomPainter {
  _IconPainter({required this.fork, required this.color});

  final bool fork;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 28);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (fork) {
      canvas
        ..drawCircle(const Offset(8, 14), 2.6, stroke)
        ..drawPath(
          Path()
            ..moveTo(10.6, 14)
            ..lineTo(13.6, 14)
            ..cubicTo(15.4, 14, 16, 13, 16, 11.6)
            ..lineTo(16, 9.8)
            ..cubicTo(16, 8.6, 16.8, 7.8, 18, 7.8)
            ..lineTo(21.2, 7.8)
            ..moveTo(13.6, 14)
            ..cubicTo(15.4, 14, 16, 15, 16, 16.4)
            ..lineTo(16, 18.2)
            ..cubicTo(16, 19.4, 16.8, 20.2, 18, 20.2)
            ..lineTo(21.2, 20.2),
          stroke,
        );
    } else {
      canvas
        ..drawRRect(
          RRect.fromLTRBR(3.5, 5.5, 24.5, 22.5, const Radius.circular(3.5)),
          stroke,
        )
        ..drawPath(
          Path()
            ..moveTo(9, 11)
            ..lineTo(12.2, 14)
            ..lineTo(9, 17)
            ..moveTo(14.5, 17.5)
            ..lineTo(19, 17.5),
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.fork != fork || old.color != color;
}

/// The check of a visited node, or the `!` of a failed one: a 17 px disc in
/// a ring of the canvas's color.
class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.fill, required this.failed});

  final Color fill;
  final bool failed;

  @override
  Widget build(BuildContext context) => Container(
    width: 21,
    height: 21,
    decoration: BoxDecoration(
      color: fill,
      shape: BoxShape.circle,
      border: Border.all(color: CanvasColors.background, width: 2),
    ),
    alignment: Alignment.center,
    child: CustomPaint(
      size: const Size.square(9),
      painter: _MarkPainter(failed: failed),
    ),
  );
}

/// A check, or an exclamation mark, in white: 10 units.
class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.failed});

  final bool failed;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 10);
    final stroke = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (failed) {
      canvas
        ..drawLine(const Offset(5, 1.2), const Offset(5, 5.6), stroke)
        ..drawCircle(
          const Offset(5, 8.4),
          1.15,
          Paint()..color = const Color(0xFFFFFFFF),
        );
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(1.6, 5.2)
          ..lineTo(3.8, 7.4)
          ..lineTo(8.4, 2.8),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.failed != failed;
}

/// The turning sign of a running node. It repaints as it turns and builds
/// nothing: a rebuild under the canvas's layout builder would lay the canvas
/// out and paint it again on every frame.
class _Spinner extends StatefulWidget {
  const _Spinner();

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turns = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: const Size.square(17),
      painter: _SpinnerPainter(_turns),
    ),
  );
}

/// A disc of the canvas's color, and on it a dim ring with a bright quarter
/// turned by [turns]: 18 units.
class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter(this.turns) : super(repaint: turns);

  final Animation<double> turns;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..scale(size.width / 18)
      ..drawCircle(
        const Offset(9, 9),
        9,
        Paint()..color = CanvasColors.background,
      )
      ..translate(9, 9)
      ..rotate(turns.value * 2 * math.pi)
      ..translate(-9, -9);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = const Color(0xFF4A3A1E);
    canvas
      ..drawCircle(const Offset(9, 9), 6.5, ring)
      ..drawArc(
        Rect.fromCircle(center: const Offset(9, 9), radius: 6.5),
        -math.pi / 2,
        math.pi / 2,
        false,
        ring
          ..color = const Color(0xFFF2A93B)
          ..strokeCap = StrokeCap.round,
      );
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) => old.turns != turns;
}

/// A run's short id over the tile, in the color of the run's state; its
/// full id in a tooltip. A running run's has no border, as in the mockups.
class _RunBadge extends StatelessWidget {
  const _RunBadge(this.phase, this.text, this.tooltip);

  final RunPhase phase;
  final String text;
  final String tooltip;

  static const _padding = 7.0;

  /// How wide the badge of [text] is for a run in [phase].
  static double widthOf(String text, RunPhase phase) =>
      measureLabel(text, LabelKind.counter) +
      2 * _padding +
      (phase == RunPhase.running ? 0 : 2);

  @override
  Widget build(BuildContext context) {
    final (fill, border, color, weight) = switch (phase) {
      RunPhase.running => (
        const Color(0xFFF2A93B),
        null,
        const Color(0xFF1F1606),
        FontWeight.w500,
      ),
      RunPhase.finished => (
        const Color(0xFF1D3328),
        const Color(0xFF2F5E44),
        const Color(0xFF8FDDB0),
        FontWeight.w400,
      ),
      RunPhase.failed => (
        const Color(0xFF3A1D20),
        const Color(0xFF6A2F34),
        const Color(0xFFF7878C),
        FontWeight.w400,
      ),
      RunPhase.notStarted || RunPhase.split => (
        CanvasColors.countFill,
        CanvasColors.countBorder,
        const Color(0xFFA7A8AE),
        FontWeight.w400,
      ),
    };
    return Tooltip(
      message: tooltip,
      child: _Pill(
        fill: fill,
        border: border,
        padding: _padding,
        child: Text(
          text,
          style: CanvasText.badge.copyWith(color: color, fontWeight: weight),
          textScaler: TextScaler.noScaling,
        ),
      ),
    );
  }
}

/// `2×` over a node entered more than once.
class _CountBadge extends StatelessWidget {
  const _CountBadge(this.text);

  final String text;

  static const _padding = 6.0;

  /// How wide the badge of [text] is.
  static double widthOf(String text) =>
      measureLabel(text, LabelKind.counter) + 2 * _padding + 2;

  @override
  Widget build(BuildContext context) => _Pill(
    fill: CanvasColors.countFill,
    border: CanvasColors.countBorder,
    padding: _padding,
    child: Text(
      text,
      style: CanvasText.badge.copyWith(color: CanvasColors.countText),
      textScaler: TextScaler.noScaling,
    ),
  );
}

/// A rounded badge with a 1 px [border], or none.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.fill,
    required this.border,
    required this.padding,
    required this.child,
  });

  final Color fill;
  final Color? border;
  final double padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: padding, vertical: 1),
    decoration: BoxDecoration(
      color: fill,
      border: border == null ? null : Border.all(color: border!),
      borderRadius: const BorderRadius.all(Radius.circular(999)),
    ),
    child: child,
  );
}
