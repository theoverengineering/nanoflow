import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../layout/layout.dart' as layout;
import '../../layout/layout.dart'
    show
        LabelKind,
        NodeKind,
        badgeHeight,
        badgeOverhang,
        copiesBadge,
        overTile,
        stackInset,
        stackStep,
        tilesBehind;
import '../../state/graph_marks.dart';
import '../../widgets/dashed_border.dart';
import '../../widgets/icons.dart';
import '../../widgets/spinner.dart';
import 'canvas_style.dart';
import 'layout_geometry.dart';

/// A node on the canvas (docs/ui-spec.md «Граф», spec §9 «Граф», «Шаги на
/// графе»): the tile of its kind with its name and place under it, a name
/// cut short whole in a tooltip. A step's tile has a terminal on it, a
/// condition's a diamond; a call's is a stack of two tiles with the steps
/// of the function on it (`{ 3 }`), copies' a stack of three with the steps
/// of a copy on it and how many copies ran across the top right of the
/// stack (`×3`; `×n` without a session); the start and end markers are
/// dashed and say so.
///
/// With a session, the tile is framed in the state of the steps on it, its
/// state's badge on its bottom right corner; a step node entered more than
/// once says so over its top right corner (`2×`), and in the body of
/// copies, all shown, how many copies are on it now. The selected step's
/// node has the accent ring.
///
/// The canvas places it at [areaOf] the node; of all that, only the tile
/// and its state's badge are clicked. A click is [onTap], a double click
/// [onDoubleTap], told where on the screen; a tile with neither is not
/// clicked.
class NodeTile extends StatelessWidget {
  NodeTile({
    required this.node,
    this.marks,
    this.selected = false,
    this.allCopies = false,
    this.copies = copiesBadge,
    this.onTap,
    this.onDoubleTap,
  }) : super(key: keyOf(node.id));

  /// The key of the widget of the node [id].
  static Key keyOf(String id) => ValueKey(('node', id));

  /// The key of the tile itself of the node [id]: what is clicked.
  static Key tileKeyOf(String id) => ValueKey(('tile', id));

  /// The key of the badge that counts the copies on a step.
  static Key runningKeyOf(String id) => ValueKey(('running', id));

  final layout.NodeBox node;

  /// What the session's steps put on the node; `null` for `Current graph`,
  /// a condition or a marker: the tile is drawn plain.
  final NodeMarks? marks;

  /// Whether the selected step is on the node, or in it: the ring.
  final bool selected;

  /// Whether a step node says how many copies are on it now: in the body of
  /// copies, all of them shown.
  final bool allCopies;

  /// The badge over the stack of copies: `×3`, `×0` muted, `×n`.
  final String copies;

  final VoidCallback? onTap;
  final ValueChanged<Offset>? onDoubleTap;

  /// How far round the tile the widget reaches: the tiles stacked behind
  /// it, the badges, the ring.
  static const _margin = 16.0;

  static const _radius = 12.0;
  static const _ring = 4.0;

  /// How far past the tile's right side the badge over it reaches.
  static const _overhang = 6.0;

  /// The canvas area a node's widget takes: its tile with what is drawn
  /// round it and over it, its texts.
  static Rect areaOf(layout.NodeBox node) {
    final tile = node.tile.toRect();
    return Rect.fromLTRB(
          tile.left - _margin,
          tile.top - math.max(_margin, overTile(node.kind)),
          tile.right + _margin,
          tile.bottom + _margin,
        )
        .expandToInclude(node.nameRect.toRect())
        .expandToInclude(node.placeRect.toRect());
  }

  @override
  Widget build(BuildContext context) {
    final area = areaOf(node);
    Rect local(layout.Rect rect) => rect.toRect().shift(-area.topLeft);
    final tile = local(node.tile);
    final look = _Look.of(marks?.state);
    final count = _countBadge();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var k = tilesBehind(node.kind); k >= 1; k--)
          Positioned.fromRect(
            rect: Rect.fromLTRB(
              tile.left + k * stackInset,
              tile.top - k * stackStep,
              tile.right - k * stackInset,
              tile.bottom - k * stackStep,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: CanvasColors.stackFill,
                border: Border.fromBorderSide(
                  BorderSide(color: look.stack, width: 1.5),
                ),
                borderRadius: const BorderRadius.all(Radius.circular(_radius)),
              ),
            ),
          ),
        _clickable(tile, look),
        if (node.kind == NodeKind.copies)
          Positioned(
            right: area.width - tile.right - badgeOverhang,
            top:
                tile.top - stackStep * tilesBehind(node.kind) - badgeHeight / 2,
            child: _CopiesBadge(copies, muted: copies == '×0'),
          ),
        if (count != null)
          Positioned(
            right: area.width - tile.right - _overhang,
            top: tile.top - 9,
            child: count,
          ),
        if (node.name case final name?)
          _text(
            local(node.nameRect),
            name,
            CanvasText.name.copyWith(
              color: look.name,
              fontWeight: selected ? FontWeight.w700 : look.nameWeight,
            ),
            tooltip: node.fullName == name ? null : node.fullName,
          ),
        if (node.place case final place?)
          _text(
            local(node.placeRect),
            place,
            CanvasText.place.copyWith(color: look.place),
          ),
      ],
    );
  }

  /// Over a step node's top right corner: in the body of copies, all
  /// shown, how many copies are on it now; else `2×` when it was entered
  /// more than once. Calls and copies have their stacks there.
  Widget? _countBadge() {
    final marks = this.marks;
    if (marks == null || node.kind != NodeKind.step) return null;
    if (allCopies && marks.running > 0) {
      return _RunningBadge(marks.running, key: runningKeyOf(node.id));
    }
    return switch (marks.visitsText) {
      final visits? => _CountBadge(visits),
      null => null,
    };
  }

  /// The tile with its state's badge on its corner: what is clicked, under
  /// the pointing hand when a click does anything. Only the two shapes are
  /// hit, not the box round them.
  Widget _clickable(Rect tile, _Look look) {
    final badge = _stateBadge(marks?.state);
    // The badge's box, 21 px with its ring, 10 px into the tile's corner.
    final badgeBox = Rect.fromLTWH(tile.right - 10, tile.bottom - 10, 21, 21);
    final region = badge == null ? tile : tile.expandToInclude(badgeBox);
    Widget shapes = Stack(
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
    );
    if (onTap != null || onDoubleTap != null) {
      shapes = MouseRegion(
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
          child: shapes,
        ),
      );
    }
    return Positioned.fromRect(rect: region, child: shapes);
  }

  Widget _tile(_Look look) {
    final inside = node.inside;
    switch (node.kind) {
      case NodeKind.start || NodeKind.end:
        return DashedBorder(
          key: tileKeyOf(node.id),
          color: CanvasColors.markerBorder,
          radius: _radius,
          child: Center(
            child: Text(
              inside!,
              style: CanvasText.marker,
              textScaler: TextScaler.noScaling,
            ),
          ),
        );
      case NodeKind.step ||
          NodeKind.condition ||
          NodeKind.call ||
          NodeKind.copies:
        return DecoratedBox(
          key: tileKeyOf(node.id),
          decoration: BoxDecoration(
            color: look.fill,
            border: Border.fromBorderSide(
              BorderSide(color: look.border, width: look.borderWidth),
            ),
            borderRadius: const BorderRadius.all(Radius.circular(_radius)),
            boxShadow: [
              if (selected)
                const BoxShadow(color: CanvasColors.ring, spreadRadius: _ring),
            ],
          ),
          child: Center(
            child: inside != null
                ? Text(
                    inside,
                    style: CanvasText.inside.copyWith(color: look.icon),
                    textScaler: TextScaler.noScaling,
                  )
                : NodeIcon(
                    fork: node.kind == NodeKind.condition,
                    size: 28,
                    color: look.icon,
                  ),
          ),
        );
    }
  }

  void _tapped(SerialTapUpDetails details) {
    switch (details.count) {
      case 1:
        onTap?.call();
      case 2:
        onDoubleTap?.call(details.globalPosition);
    }
  }

  /// [text] centred on [rect] in [style]; [tooltip] over it, when given.
  static Widget _text(
    Rect rect,
    String text,
    TextStyle style, {
    String? tooltip,
  }) {
    final height = style.fontSize! * style.height!;
    // Room on both sides, so a text a hair wider than measured still fits.
    const slack = 20.0;
    final shown = Text(
      text,
      style: style,
      textAlign: TextAlign.center,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
    );
    return Positioned(
      left: rect.left - slack,
      top: rect.top + (rect.height - height) / 2,
      width: rect.width + 2 * slack,
      child: tooltip == null ? shown : Tooltip(message: tooltip, child: shown),
    );
  }

  static Widget? _stateBadge(NodeState? state) => switch (state) {
    NodeState.visited => const _StateBadge(
      fill: Color(0xFF2A9D61),
      failed: false,
    ),
    NodeState.failed => const _StateBadge(
      fill: Color(0xFFD9434A),
      failed: true,
    ),
    NodeState.running => const Spinner(
      size: 17,
      strokeWidth: 2.2,
      background: CanvasColors.background,
    ),
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
    required this.place,
    this.stack = CanvasColors.stackBorder,
  });

  final Color fill;
  final Color border;
  final double borderWidth;
  final Color icon;
  final Color name;
  final FontWeight nameWeight;
  final Color place;

  /// The outline of the tiles stacked behind a call or copies.
  final Color stack;

  static _Look of(NodeState? state) => switch (state) {
    null => plain,
    NodeState.notVisited => notVisited,
    NodeState.visited => visited,
    NodeState.running => running,
    NodeState.failed => failed,
  };

  /// `Current graph`, a condition, a marker: no state.
  static const plain = _Look(
    fill: CanvasColors.tileFill,
    border: CanvasColors.tileBorder,
    borderWidth: 1.5,
    icon: CanvasColors.icon,
    name: CanvasColors.name,
    nameWeight: FontWeight.w600,
    place: CanvasColors.place,
  );

  static const notVisited = _Look(
    fill: Color(0xFF2C2D32),
    border: Color(0xFF45464C),
    borderWidth: 1.5,
    icon: Color(0xFF6E6F76),
    name: Color(0xFF9A9BA2),
    nameWeight: FontWeight.w500,
    place: Color(0xFF8A8B92),
    stack: Color(0xFF45464C),
  );

  static const visited = _Look(
    fill: CanvasColors.tileFill,
    border: Color(0xFF3CC47C),
    borderWidth: 2,
    icon: CanvasColors.icon,
    name: CanvasColors.name,
    nameWeight: FontWeight.w600,
    place: CanvasColors.place,
  );

  static const running = _Look(
    fill: Color(0xFF36302A),
    border: Color(0xFFF2A93B),
    borderWidth: 2,
    icon: Color(0xFFF2A93B),
    name: Color(0xFFF7F3EA),
    nameWeight: FontWeight.w600,
    place: Color(0xFFC9A36A),
  );

  static const failed = _Look(
    fill: Color(0xFF382A2C),
    border: Color(0xFFF0555C),
    borderWidth: 2,
    icon: Color(0xFFF0555C),
    name: Color(0xFFF7ECEC),
    nameWeight: FontWeight.w600,
    place: Color(0xFFC98A8D),
  );
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

/// How many copies are on a step now, in the color of running steps
/// (docs/design/code-first/copies-frame.html).
class _RunningBadge extends StatelessWidget {
  const _RunningBadge(this.copies, {super.key});

  final int copies;

  static const _size = 17.0;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: _size),
    height: _size,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: Color(0xFFF2A93B),
      borderRadius: BorderRadius.all(Radius.circular(_size / 2)),
    ),
    child: Text(
      '$copies',
      style: CanvasText.badge.copyWith(
        color: const Color(0xFF1F1606),
        fontWeight: FontWeight.w500,
      ),
      textScaler: TextScaler.noScaling,
    ),
  );
}

/// `2×` over a node entered more than once.
class _CountBadge extends StatelessWidget {
  const _CountBadge(this.text);

  final String text;

  /// How wide the badge of [text] is.
  static double widthOf(String text) =>
      measureLabel(text, LabelKind.counter) + 14;

  @override
  Widget build(BuildContext context) => Container(
    width: widthOf(text),
    padding: const EdgeInsets.symmetric(vertical: 1),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: CanvasColors.badgeFill,
      border: Border.all(color: CanvasColors.badgeBorder),
      borderRadius: const BorderRadius.all(Radius.circular(999)),
    ),
    child: Text(
      text,
      style: CanvasText.badge,
      textScaler: TextScaler.noScaling,
    ),
  );
}

/// How many copies ran, across the top right of the stack of copies: `×3`;
/// `×0` muted while none has; `×n` without a session.
class _CopiesBadge extends StatelessWidget {
  const _CopiesBadge(this.text, {required this.muted});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) => Container(
    height: badgeHeight,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: CanvasColors.badgeFill,
      border: Border.fromBorderSide(
        BorderSide(color: CanvasColors.badgeBorder),
      ),
      borderRadius: BorderRadius.all(Radius.circular(badgeHeight / 2)),
    ),
    child: Text(
      text,
      style: muted
          ? CanvasText.badge.copyWith(color: CanvasColors.markerText)
          : CanvasText.badge,
      textScaler: TextScaler.noScaling,
    ),
  );
}
