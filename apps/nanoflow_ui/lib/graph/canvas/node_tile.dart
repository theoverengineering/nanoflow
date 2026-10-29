import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../layout/layout.dart' as layout;
import '../../layout/layout.dart' show NodeKind;
import '../../state/graph_marks.dart';
import '../../widgets/clickable.dart';
import '../../widgets/dashed_border.dart';
import '../../widgets/doc_text.dart';
import '../../widgets/icons.dart';
import 'canvas_style.dart';
import 'frame_toggle.dart';
import 'layout_geometry.dart';
import 'open_as_graph_button.dart';
import 'tile_marks.dart';

/// A node on the canvas (docs/ui-spec.md «Граф», spec §9 «Граф», «Эффекты на
/// графе»): the tile of its kind with its name and place under it, a name
/// cut short whole in a tooltip. An effect's tile has a terminal on it, a
/// condition's a branch; a call's `ƒ`, a function, with the effects of the
/// function small under it (`{ 3 }`); the start and end markers are dashed
/// and say so.
///
/// With a session, the tile is framed in the state of the effects on it, its
/// state's badge on its bottom right corner; an effect node entered more than
/// once says so over its top right corner (`2×`). A fork the code went
/// through looks as a visited effect, `2×` over it as over one; one it did
/// not is plain. The looks and the badges are in tile_marks.dart. The ring
/// round the selected effect's node is not the tile's: the canvas draws it
/// under the arrows ([ringOf]).
///
/// A call that can be expanded in place has `+` in its tile's top right
/// corner: [onExpand], told where on the screen (decision 6). A
/// call whose function can be opened as the main graph has ↗ left of it —
/// in the corner without `+`: [onOpenAsGraph], told the same (open-as-graph
/// design §2).
///
/// An effect or a call with a [doc] shows it when the pointer rests on the
/// tile (node docs design §4.2).
///
/// The place under the name is a link with [onOpenPlace]: a click opens it
/// in the editor at its line.
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
    this.onTap,
    this.onDoubleTap,
    this.onExpand,
    this.onOpenAsGraph,
    this.onOpenPlace,
    this.doc,
  }) : id = id ?? node.id,
       super(key: keyOf(id ?? node.id));

  /// The key of the widget of the node [id].
  static Key keyOf(String id) => ValueKey(('node', id));

  /// The key of the tile itself of the node [id]: what is clicked.
  static Key tileKeyOf(String id) => ValueKey(('tile', id));

  /// The key of the ring round the node [id], the selected effect's.
  static Key ringKeyOf(String id) => ValueKey(('ring', id));

  /// The key of the place under the node [id] when it is a link.
  static Key placeKeyOf(String id) => ValueKey(('place', id));

  /// What the place under a tile says it does, in its tooltip.
  static const openPlaceTooltip = 'Open in editor';

  final layout.NodeBox node;

  /// The node's id on the canvas.
  final String id;

  /// What the session's effects put on the node; `null` for `Current graph`,
  /// a fork the code did not go through or a marker: the tile is drawn
  /// plain.
  final NodeMarks? marks;

  final VoidCallback? onTap;
  final ValueChanged<Offset>? onDoubleTap;

  /// Expands the call in place; `null` for a node that does not.
  final ValueChanged<Offset>? onExpand;

  /// Opens the call's function as the main graph; `null` for a node that
  /// does not.
  final ValueChanged<Offset>? onOpenAsGraph;

  /// Opens the node's place in the editor at its line; `null` for a node
  /// whose place is plain text.
  final VoidCallback? onOpenPlace;

  /// What the node's doc says, or the docs of the functions a call goes to,
  /// in a tooltip over the tile; `null` for none.
  final InlineSpan? doc;

  /// How far round the tile the widget reaches: the badges, the ring.
  static const _margin = 16.0;

  static const _radius = 12.0;

  /// The side of the icon on a tile.
  static const _iconSize = 28.0;

  /// How far the ring round the selected effect's node reaches out of its
  /// tile.
  static const ring = 4.0;

  /// How far past the tile's right side the badge over it reaches.
  static const _overhang = 6.0;

  /// How far in from the tile's top right corner the `+` is.
  static const _toggleInset = 4.0;

  /// Where on the screen the `+` or ↗ built in [context] ends: the menu of
  /// a call's functions opens there.
  static Offset _globalOf(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset(FrameToggle.size, FrameToggle.size));
  }

  /// The ring round the tile of [node], the selected effect's node, [id] on
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
          tile.top - _margin,
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
        _clickable(tile, look),
        if (count != null)
          Positioned(
            right: area.width - tile.right - _overhang,
            // Over a call, higher: clear of its + and ↗.
            top: tile.top - (node.kind == NodeKind.call ? 14 : 9),
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
        if (onOpenAsGraph case final open?)
          Positioned(
            left:
                tile.right -
                _toggleInset -
                (onExpand == null ? 0 : FrameToggle.size) -
                OpenAsGraphButton.size,
            top: tile.top + _toggleInset,
            child: Builder(
              builder: (context) => OpenAsGraphButton(
                key: OpenAsGraphButton.keyOf(id),
                onTap: () => open(_globalOf(context)),
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
          if (onOpenPlace case final open?)
            _link(
              local(node.placeRect),
              place,
              CanvasText.place.copyWith(color: look.place),
              onTap: open,
            )
          else
            _text(
              local(node.placeRect),
              place,
              CanvasText.place.copyWith(color: look.place),
            ),
      ],
    );
  }

  /// Over an effect node's top right corner: `2×` when it was entered more
  /// than once. Over a fork's, `2×` when the code went through it more than
  /// once, and over a call's when it ran more than once.
  Widget? _countBadge() {
    final marks = this.marks;
    if (marks == null ||
        (node.kind != NodeKind.effect &&
            node.kind != NodeKind.condition &&
            node.kind != NodeKind.call)) {
      return null;
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
    return Positioned.fromRect(
      rect: region,
      child: DocTooltip(message: doc, child: shapes),
    );
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
      case NodeKind.effect:
        return _framed(look, EffectIcon(size: _iconSize, color: look.icon));
      case NodeKind.condition:
        return _framed(look, ConditionIcon(size: _iconSize, color: look.icon));
      case NodeKind.call:
        return _framed(
          look,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FunctionIcon(size: _iconSize, color: look.icon),
              Text(
                inside!,
                style: CanvasText.inside.copyWith(color: look.inside),
                textScaler: TextScaler.noScaling,
              ),
            ],
          ),
        );
    }
  }

  /// The tile filled and framed in [look], [content] in its middle.
  Widget _framed(TileLook look, Widget content) => DecoratedBox(
    key: tileKeyOf(id),
    decoration: BoxDecoration(
      color: look.fill,
      border: Border.fromBorderSide(
        BorderSide(color: look.border, width: look.borderWidth),
      ),
      borderRadius: const BorderRadius.all(Radius.circular(_radius)),
    ),
    child: Center(child: content),
  );

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
    final shown = _line(text, style);
    return _centred(
      rect,
      style,
      tooltip == null ? shown : Tooltip(message: tooltip, child: shown),
    );
  }

  /// [text] centred on [rect] in [style], a link to [onTap]: underlined and
  /// lighter under the pointer, [openPlaceTooltip] over it. Only the text is
  /// clicked, not the room round it.
  Widget _link(
    Rect rect,
    String text,
    TextStyle style, {
    required VoidCallback onTap,
  }) => _centred(
    rect,
    style,
    Center(
      child: Tooltip(
        message: openPlaceTooltip,
        child: Clickable.hover(
          key: placeKeyOf(id),
          onTap: onTap,
          builder: (context, hovered) => _line(
            text,
            hovered
                ? style.copyWith(
                    color: CanvasColors.link,
                    decoration: TextDecoration.underline,
                    decorationColor: CanvasColors.link,
                  )
                : style,
          ),
        ),
      ),
    ),
  );

  /// [child], a line of text in [style], centred on [rect].
  static Widget _centred(Rect rect, TextStyle style, Widget child) {
    final height = style.fontSize! * style.height!;
    // Room on both sides, so a text a hair wider than measured still fits.
    const slack = 20.0;
    return Positioned(
      left: rect.left - slack,
      top: rect.top + (rect.height - height) / 2,
      width: rect.width + 2 * slack,
      child: child,
    );
  }

  static Widget _line(String text, TextStyle style) => Text(
    text,
    style: style,
    textAlign: TextAlign.center,
    textScaler: TextScaler.noScaling,
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.visible,
  );
}
