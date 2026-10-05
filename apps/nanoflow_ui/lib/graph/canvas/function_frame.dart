import 'package:flutter/material.dart';

import '../../layout/layout.dart' as layout;
import 'canvas_style.dart';
import 'frame_toggle.dart';

/// The frame of a call expanded in place (decision 6;
/// docs/design/code-first/function-frames.html): a gray solid outline, the
/// tiles' border, with nothing in it but the body of the function — the
/// same at any depth, so that frames in frames neither darken nor clutter;
/// the function's name, `publish()`, in its top left corner, and `−` to
/// collapse it in its top right corner.
///
/// It fills the frame; the body is drawn over it.
class FunctionFrameView extends StatelessWidget {
  const FunctionFrameView({
    super.key,
    required this.title,
    required this.onCollapse,
    this.collapseKey,
  });

  /// `publish()`.
  final String title;

  final VoidCallback onCollapse;

  /// The key of the `−`.
  final Key? collapseKey;

  static const _radius = 12.0;
  static const _inset = 16.0;
  static const _titleTop = 10.0;
  static const _toggleInset = 7.0;
  static const _titleGap = 12.0;

  /// The room the frame keeps round the body of the function [title]: the
  /// title row over it, and wide enough for the title and the `−`.
  static layout.FrameRoom roomFor(String title) => layout.FrameRoom(
    top: 32,
    side: _inset,
    bottom: _inset,
    width:
        _inset +
        measureText(title, CanvasText.frameTitle) +
        _titleGap +
        FrameToggle.size +
        _toggleInset,
  );

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      const Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.fromBorderSide(
              BorderSide(
                color: CanvasColors.tileBorder,
                width: layout.frameOutline,
              ),
            ),
            borderRadius: BorderRadius.all(Radius.circular(_radius)),
          ),
        ),
      ),
      Positioned(
        left: _inset,
        top: _titleTop,
        child: Text(
          title,
          style: CanvasText.frameTitle,
          textScaler: TextScaler.noScaling,
          maxLines: 1,
          softWrap: false,
        ),
      ),
      Positioned(
        right: _toggleInset,
        top: _toggleInset,
        child: FrameToggle.collapse(key: collapseKey, onTap: onCollapse),
      ),
    ],
  );
}
