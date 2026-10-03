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
import '../../widgets/dashed_border.dart';
import '../../widgets/icons.dart';
import 'canvas_style.dart';
import 'layout_geometry.dart';

/// A node on the canvas (docs/ui-spec.md «Граф», spec §9 «Граф»): the tile
/// of its kind with its name and place under it, a name cut short whole in
/// a tooltip. A step's tile has a terminal on it, a condition's a diamond;
/// a call's is a stack of two tiles with the steps of the function on it
/// (`{ 3 }`), copies' a stack of three with the steps of a copy on it and
/// `×n` across the top right of the stack; the start and end markers are
/// dashed and say so.
///
/// The canvas places it at [areaOf] the node; of all that, only the tile is
/// clicked. A click is [onTap], a double click [onDoubleTap], told where
/// on the screen; a tile with neither is not clicked.
class NodeTile extends StatelessWidget {
  NodeTile({required this.node, this.onTap, this.onDoubleTap})
    : super(key: keyOf(node.id));

  /// The key of the widget of the node [id].
  static Key keyOf(String id) => ValueKey(('node', id));

  /// The key of the tile itself of the node [id]: what is clicked.
  static Key tileKeyOf(String id) => ValueKey(('tile', id));

  final layout.NodeBox node;

  final VoidCallback? onTap;
  final ValueChanged<Offset>? onDoubleTap;

  /// How far round the tile the widget reaches: the tiles stacked behind
  /// it, the badges.
  static const _margin = 16.0;

  static const _radius = 12.0;

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
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: CanvasColors.stackFill,
                border: Border.fromBorderSide(
                  BorderSide(color: CanvasColors.stackBorder, width: 1.5),
                ),
                borderRadius: BorderRadius.all(Radius.circular(_radius)),
              ),
            ),
          ),
        Positioned.fromRect(rect: tile, child: _clickable(_tile())),
        if (node.kind == NodeKind.copies)
          Positioned(
            right: area.width - tile.right - badgeOverhang,
            top:
                tile.top - stackStep * tilesBehind(node.kind) - badgeHeight / 2,
            child: const _CopiesBadge(),
          ),
        if (node.name case final name?)
          _text(
            local(node.nameRect),
            name,
            CanvasText.name.copyWith(color: CanvasColors.name),
            tooltip: node.fullName == name ? null : node.fullName,
          ),
        if (node.place case final place?)
          _text(
            local(node.placeRect),
            place,
            CanvasText.place.copyWith(color: CanvasColors.place),
          ),
      ],
    );
  }

  /// [tile] under the pointing hand, when a click does anything.
  Widget _clickable(Widget tile) {
    if (onTap == null && onDoubleTap == null) return tile;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: RawGestureDetector(
        gestures: {
          SerialTapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<SerialTapGestureRecognizer>(
                SerialTapGestureRecognizer.new,
                (recognizer) => recognizer.onSerialTapUp = _tapped,
              ),
        },
        child: tile,
      ),
    );
  }

  Widget _tile() {
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
          decoration: const BoxDecoration(
            color: CanvasColors.tileFill,
            border: Border.fromBorderSide(
              BorderSide(color: CanvasColors.tileBorder, width: 1.5),
            ),
            borderRadius: BorderRadius.all(Radius.circular(_radius)),
          ),
          child: Center(
            child: inside != null
                ? Text(
                    inside,
                    style: CanvasText.inside,
                    textScaler: TextScaler.noScaling,
                  )
                : NodeIcon(
                    fork: node.kind == NodeKind.condition,
                    size: 28,
                    color: CanvasColors.icon,
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

/// `×n` across the top right of the stack of copies: copies run side by
/// side, as many as the list has items.
class _CopiesBadge extends StatelessWidget {
  const _CopiesBadge();

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
      copiesBadge,
      style: CanvasText.badge,
      textScaler: TextScaler.noScaling,
    ),
  );
}
