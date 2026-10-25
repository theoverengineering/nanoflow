import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../layout/layout.dart' as layout;
import 'canvas_style.dart';
import 'frame_toggle.dart';

/// Where the frame round the body of copies is, in the coordinates of the
/// body's layout: [frame] itself, and [extent], what is drawn of it with
/// the outlines stacked behind it.
final class CopiesFrameBox {
  const CopiesFrameBox._(this.frame, this.extent, this.switcherTop);

  /// The room the frame keeps round the body of copies: over it for
  /// [title] and [count] on one line — and the `−` when it is
  /// [collapsible], drawn in place —, then for a switcher [switcher] wide
  /// when there is one (`null` without a session); under it for how the
  /// copies stand; on its sides. The frame is as wide as the widest of
  /// them; the outlines behind it reach over it and right of it.
  static layout.FrameRoom roomFor({
    required String title,
    required String count,
    required double? switcher,
    bool collapsible = false,
  }) {
    final header =
        measureText(title, CanvasText.frameTitle) +
        _titleGap +
        measureText(count, CanvasText.frameCount) +
        (collapsible ? _toggleGap + FrameToggle.size : 0);
    return layout.FrameRoom(
      top:
          _titleTop +
          _titleHeight +
          (switcher == null ? 0 : _rowGap + _switcherHeight) +
          _bodyGap,
      side: _side,
      bottom: _bottom,
      width: math.max(header, switcher ?? 0) + 2 * _inset,
      above: 2 * CopiesFrameView.stackStep,
    );
  }

  /// The frame round [body], the layout of the body of copies opened, with
  /// the room [roomFor] keeps; the body in its middle.
  factory CopiesFrameBox.around(
    Rect body, {
    required String title,
    required String count,
    required double? switcher,
  }) {
    final room = roomFor(title: title, count: count, switcher: switcher);
    final width = math.max(body.width + 2 * room.side, room.width);
    return CopiesFrameBox.at(
      Rect.fromLTWH(
        body.center.dx - width / 2,
        body.top - room.top,
        width,
        room.top + body.height + room.bottom,
      ),
      switcher: switcher != null,
    );
  }

  /// The frame [frame], with a [switcher] or without.
  factory CopiesFrameBox.at(Rect frame, {required bool switcher}) =>
      CopiesFrameBox._(
        frame,
        Rect.fromLTRB(
          frame.left,
          frame.top - 2 * CopiesFrameView.stackStep,
          frame.right + 2 * CopiesFrameView.stackStep,
          frame.bottom,
        ),
        switcher ? _titleTop + _titleHeight + _rowGap : null,
      );

  /// The frame.
  final Rect frame;

  /// The frame and the outlines stacked behind it.
  final Rect extent;

  /// How far under the frame's top the switcher is; `null` without one.
  final double? switcherTop;

  static const _side = 24.0;
  static const _inset = 16.0;
  static const _titleTop = 12.0;
  static const _titleHeight = 16.0;
  static const _titleGap = 24.0;
  static const _rowGap = 10.0;
  static const _switcherHeight = 22.0;
  static const _bodyGap = 14.0;
  static const _bottom = 30.0;
  static const _toggleGap = 8.0;
}

/// The frame round the body of copies drawn on the canvas (decisions 10
/// and 11; docs/design/code-first/copies-frame.html, copy-switcher.html):
/// two outlines stacked behind it, up and to the right — several copies;
/// over the body, what the copies are of, `each pkg in packages`, and how
/// many run side by side, `×3 · in parallel`; with a session, the copy
/// [switcher] under them, and in the bottom right corner how the copies
/// stand: `done 1 of 3`, `pkg 2 · now verify`. Drawn in place, `−` in its
/// top right corner collapses it ([onCollapse]).
///
/// It fills [box]'s extent; the body is drawn over it.
class CopiesFrameView extends StatelessWidget {
  const CopiesFrameView({
    super.key,
    required this.box,
    required this.title,
    required this.count,
    this.switcher,
    this.footer,
    this.onCollapse,
    this.collapseKey,
  });

  final CopiesFrameBox box;

  /// `each pkg in packages`.
  final String title;

  /// `×3 · in parallel`.
  final String count;

  final Widget? switcher;

  /// `done 1 of 3`; `null` without a session.
  final String? footer;

  /// Collapses the frame drawn in place to its tile; `null` for the body
  /// opened.
  final VoidCallback? onCollapse;

  /// The key of the `−`.
  final Key? collapseKey;

  /// How far up and to the right each outline behind the frame is.
  static const stackStep = 6.0;

  static const _radius = 12.0;

  /// The key of the text under the frame.
  static const footerKey = ValueKey('copies footer');

  @override
  Widget build(BuildContext context) {
    final origin = box.extent.topLeft;
    final frame = box.frame.shift(-origin);
    Widget outline(double k, Color color) => Positioned.fromRect(
      rect: frame.shift(Offset(k * stackStep, -k * stackStep)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: const BorderRadius.all(Radius.circular(_radius)),
        ),
      ),
    );
    Widget text(String text, TextStyle style, {Key? key}) => Text(
      text,
      key: key,
      style: style,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
      softWrap: false,
    );
    const inset = CopiesFrameBox._inset;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        outline(2, const Color(0xFF3A3A40)),
        outline(1, const Color(0xFF45464B)),
        Positioned.fromRect(
          rect: frame,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: CanvasColors.background,
              border: Border.fromBorderSide(
                BorderSide(
                  color: Color(0xFF6E6F76),
                  width: layout.frameOutline,
                ),
              ),
              borderRadius: BorderRadius.all(Radius.circular(_radius)),
            ),
          ),
        ),
        Positioned(
          left: frame.left + inset,
          top: frame.top + CopiesFrameBox._titleTop,
          child: text(title, CanvasText.frameTitle),
        ),
        Positioned(
          right:
              box.extent.width -
              frame.right +
              inset +
              (onCollapse == null
                  ? 0
                  : CopiesFrameBox._toggleGap + FrameToggle.size),
          top: frame.top + CopiesFrameBox._titleTop,
          child: text(count, CanvasText.frameCount),
        ),
        if (onCollapse case final collapse?)
          Positioned(
            right: box.extent.width - frame.right + inset,
            top:
                frame.top +
                CopiesFrameBox._titleTop +
                (CopiesFrameBox._titleHeight - FrameToggle.size) / 2,
            child: FrameToggle.collapse(key: collapseKey, onTap: collapse),
          ),
        if ((switcher, box.switcherTop) case (final switcher?, final top?))
          Positioned(
            left: frame.left + inset,
            top: frame.top + top,
            child: switcher,
          ),
        if (footer case final footer?)
          Positioned(
            right: box.extent.width - frame.right + inset,
            bottom: box.extent.height - frame.bottom + 8,
            child: text(footer, CanvasText.frameFooter, key: footerKey),
          ),
      ],
    );
  }
}
