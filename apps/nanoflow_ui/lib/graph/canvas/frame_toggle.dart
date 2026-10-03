import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/clickable.dart';

/// The button that expands a call or copies in place, `+` on its tile, and
/// collapses its frame back to the tile, `−` in the frame's top right
/// corner (decision 6; docs/design/code-first/function-frames.html).
class FrameToggle extends StatelessWidget {
  const FrameToggle.expand({super.key, required this.onTap}) : expands = true;

  const FrameToggle.collapse({super.key, required this.onTap})
    : expands = false;

  /// Whether it expands: `+`; else it collapses: `−`.
  final bool expands;

  final VoidCallback onTap;

  /// The side of the square it is clicked in.
  static const size = 18.0;

  /// The key of the `+` on the tile of the node [id] of the canvas.
  static Key expandKeyOf(String id) => ValueKey(('expand', id));

  /// The key of the `−` on the frame of the node [id] of the canvas.
  static Key collapseKeyOf(String id) => ValueKey(('collapse', id));

  static const _color = Color(0xFF8E8E96);
  static const _hover = Color(0xFFD6D6DC);

  @override
  Widget build(BuildContext context) => Tooltip(
    message: expands ? 'Expand in place' : 'Collapse',
    child: Clickable.hover(
      onTap: onTap,
      builder: (context, hovered) => SizedBox.square(
        dimension: size,
        child: Center(
          child: Text(
            expands ? '+' : '−',
            style: TextStyle(
              inherit: false,
              fontFamily: AppText.sans,
              fontSize: 15,
              height: 1,
              color: hovered ? _hover : _color,
            ),
            textScaler: TextScaler.noScaling,
          ),
        ),
      ),
    ),
  );
}
