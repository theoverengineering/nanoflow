import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';
import 'canvas_style.dart';

/// Where the frame round the body of copies is, in the coordinates of the
/// body's layout: [frame] itself, and [extent], what is drawn of it with
/// the outlines stacked behind it.
final class CopiesFrameBox {
  const CopiesFrameBox._(this.frame, this.extent, this.switcherTop);

  /// The frame round [body], the layout of the body of copies: room over it
  /// for [title] and [count] on one line, then for a switcher [switcher]
  /// wide when there is one (`null` without a session); room under it for
  /// how the copies stand. The frame is as wide as the widest of them; the
  /// body is in its middle.
  factory CopiesFrameBox.around(
    Rect body, {
    required String title,
    required String count,
    required double? switcher,
  }) {
    final top =
        _titleTop +
        _titleHeight +
        (switcher == null ? 0 : _rowGap + _switcherHeight) +
        _bodyGap;
    final header =
        _measure(title, CopiesFrameView.titleStyle) +
        _titleGap +
        _measure(count, CopiesFrameView.countStyle);
    final width = [
      body.width + 2 * _side,
      header + 2 * _inset,
      (switcher ?? 0) + 2 * _inset,
    ].reduce(math.max);
    final left = body.center.dx - width / 2;
    final frame = Rect.fromLTWH(
      left,
      body.top - top,
      width,
      top + body.height + _bottom,
    );
    return CopiesFrameBox._(
      frame,
      Rect.fromLTRB(
        frame.left,
        frame.top - 2 * CopiesFrameView.stackStep,
        frame.right + 2 * CopiesFrameView.stackStep,
        frame.bottom,
      ),
      switcher == null ? null : _titleTop + _titleHeight + _rowGap,
    );
  }

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

  static double _measure(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

/// The frame round the body of copies drawn on the canvas (decisions 10
/// and 11; docs/design/code-first/copies-frame.html, copy-switcher.html):
/// two outlines stacked behind it, up and to the right — several copies;
/// over the body, what the copies are of, `each pkg in packages`, and how
/// many run side by side, `×3 · in parallel`; with a session, the copy
/// [switcher] under them, and in the bottom right corner how the copies
/// stand: `done 1 of 3`, `copy 2 · now verify`.
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
  });

  final CopiesFrameBox box;

  /// `each pkg in packages`.
  final String title;

  /// `×3 · in parallel`.
  final String count;

  final Widget? switcher;

  /// `done 1 of 3`; `null` without a session.
  final String? footer;

  /// How far up and to the right each outline behind the frame is.
  static const stackStep = 6.0;

  static const titleStyle = TextStyle(
    inherit: false,
    fontFamily: AppText.sans,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: Color(0xFFD6D6DC),
  );

  static const countStyle = TextStyle(
    inherit: false,
    fontFamily: AppText.sans,
    fontSize: 12,
    height: 1.3,
    color: Color(0xFFA9A9B2),
  );

  static const footerStyle = TextStyle(
    inherit: false,
    fontFamily: AppText.sans,
    fontSize: 10,
    height: 1.3,
    color: Color(0xFF8E8E96),
  );

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
                BorderSide(color: Color(0xFF5A5A62)),
              ),
              borderRadius: BorderRadius.all(Radius.circular(_radius)),
            ),
          ),
        ),
        Positioned(
          left: frame.left + inset,
          top: frame.top + CopiesFrameBox._titleTop,
          child: text(title, titleStyle),
        ),
        Positioned(
          right: box.extent.width - frame.right + inset,
          top: frame.top + CopiesFrameBox._titleTop,
          child: text(count, countStyle),
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
            child: text(footer, footerStyle, key: footerKey),
          ),
      ],
    );
  }
}
