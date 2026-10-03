import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../layout/layout.dart' as layout;
import '../../layout/layout.dart'
    show
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
import 'canvas_style.dart';
import 'frame_toggle.dart';
import 'layout_geometry.dart';
import 'tile_marks.dart';

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
/// once says so over its top right corner (`2×`) — in the body of copies,
/// all shown, how many copies are on it now instead. The looks and the
/// badges are in tile_marks.dart. The ring round the selected step's node
/// is not the tile's: the canvas draws it under the arrows ([ringOf]).
///
/// A call or copies that can be expanded in place has `+` in its tile's
/// top right corner: [onExpand], told where on the screen (decision 6).
///
/// The canvas places it at [areaOf] the node; of all that, only the tile
/// and its state's badge are clicked. A click is [onTap], a double click
/// [onDoubleTap], told where on the screen; a tile with neither is not
/// clicked.
///
/// Its keys are of the node's [id] on the canvas: a node in a frame drawn
/// in place by the ids of the frames it is in and its own, joined by `/`.
class NodeTile extends StatelessWidget {
  NodeTile({
    required this.node,
    String? id,
    this.marks,
    this.allCopies = false,
    this.copies = copiesBadge,
    this.onTap,
    this.onDoubleTap,
    this.onExpand,
  }) : id = id ?? node.id,
       super(key: keyOf(id ?? node.id));

  /// The key of the widget of the node [id].
  static Key keyOf(String id) => ValueKey(('node', id));

  /// The key of the tile itself of the node [id]: what is clicked.
  static Key tileKeyOf(String id) => ValueKey(('tile', id));

  /// The key of the badge that counts the copies on a step.
  static Key runningKeyOf(String id) => ValueKey(('running', id));

  /// The key of the ring round the node [id], the selected step's.
  static Key ringKeyOf(String id) => ValueKey(('ring', id));

  final layout.NodeBox node;

  /// The node's id on the canvas.
  final String id;

  /// What the session's steps put on the node; `null` for `Current graph`,
  /// a condition or a marker: the tile is drawn plain.
  final NodeMarks? marks;

  /// Whether a step node says how many copies are on it now: in the body of
  /// copies, all of them shown.
  final bool allCopies;

  /// The badge over the stack of copies: `×3`, `×0` muted, `×n`.
  final String copies;

  final VoidCallback? onTap;
  final ValueChanged<Offset>? onDoubleTap;

  /// Expands the call or copies in place; `null` for a node that does not.
  final ValueChanged<Offset>? onExpand;

  /// How far round the tile the widget reaches: the tiles stacked behind
  /// it, the badges, the ring.
  static const _margin = 16.0;

  static const _radius = 12.0;

  /// How far the ring round the selected step's node reaches out of its
  /// tile.
  static const ring = 4.0;

  /// How far past the tile's right side the badge over it reaches.
  static const _overhang = 6.0;

  /// How far in from the tile's top right corner the `+` is.
  static const _toggleInset = 4.0;

  /// Where on the screen the `+` built in [context] ends: the menu of a
  /// call's functions opens there.
  static Offset _globalOf(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset(FrameToggle.size, FrameToggle.size));
  }

  /// The ring round the tile of [node], the selected step's node, [id] on
  /// the canvas: for the layer under the arrows and exits, so the bar of
  /// the node's input and the half of its exit dot stay over it.
  static Widget ringOf(layout.NodeBox node, String id) => Positioned.fromRect(
    key: ringKeyOf(id),
    rect: node.tile.toRect().inflate(ring),
    child: const DecoratedBox(
      decoration: BoxDecoration(
        color: CanvasColors.ring,
        borderRadius: BorderRadius.all(Radius.circular(_radius + ring)),
      ),
    ),
  );

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
    final look = TileLook.of(marks?.state);
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
            child: CopiesBadge(copies, muted: marks?.copies == 0),
          ),
        if (count != null)
          Positioned(
            right: area.width - tile.right - _overhang,
            top: tile.top - 9,
            child: count,
          ),
        if (onExpand case final expand?)
          Positioned(
            left: tile.right - FrameToggle.size - _toggleInset,
            top: tile.top + _toggleInset,
            child: Builder(
              builder: (context) => FrameToggle.expand(
                key: FrameToggle.expandKeyOf(id),
                onTap: () => expand(_globalOf(context)),
              ),
            ),
          ),
        if (node.name case final name?)
          _text(
            local(node.nameRect),
            name,
            CanvasText.name.copyWith(
              color: look.name,
              fontWeight: look.nameWeight,
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
  /// shown, how many copies are on it now, if any; else `2×` when it was
  /// entered more than once. Calls and copies have their stacks there.
  Widget? _countBadge() {
    final marks = this.marks;
    if (marks == null || node.kind != NodeKind.step) return null;
    // In copies, how many copies are on the step — the steps all of them
    // passed have nothing over them (docs/design/code-first/copies-frame.html).
    if (allCopies) {
      return marks.running > 0
          ? RunningBadge(marks.running, key: runningKeyOf(id))
          : null;
    }
    return switch (marks.visitsText) {
      final visits? => CountBadge(visits),
      null => null,
    };
  }

  /// The tile with its state's badge on its corner: what is clicked, under
  /// the pointing hand when a click does anything. Only the two shapes are
  /// hit, not the box round them.
  Widget _clickable(Rect tile, TileLook look) {
    final badge = stateBadge(marks?.state);
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

  Widget _tile(TileLook look) {
    final inside = node.inside;
    switch (node.kind) {
      case NodeKind.start || NodeKind.end:
        return DashedBorder(
          key: tileKeyOf(id),
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
          key: tileKeyOf(id),
          decoration: BoxDecoration(
            color: look.fill,
            border: Border.fromBorderSide(
              BorderSide(color: look.border, width: look.borderWidth),
            ),
            borderRadius: const BorderRadius.all(Radius.circular(_radius)),
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
}
