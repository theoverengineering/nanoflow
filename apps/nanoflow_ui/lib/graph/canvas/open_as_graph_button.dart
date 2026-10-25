import 'package:flutter/material.dart';

import '../../widgets/clickable.dart';
import '../../widgets/icons.dart';
import 'frame_toggle.dart';

/// The button that opens the function of a call as the main graph of the
/// screen, ↗ on the call's tile left of its `+`, as large and as muted as
/// it (open-as-graph design §2): the called graph drawn from its top, with
/// every session it ran in.
class OpenAsGraphButton extends StatelessWidget {
  const OpenAsGraphButton({super.key, required this.onTap});

  final VoidCallback onTap;

  /// The side of the square it is clicked in: the `+`'s.
  static const size = FrameToggle.size;

  /// The key of the ↗ on the tile of the node [id] of the canvas.
  static Key keyOf(String id) => ValueKey(('open as graph', id));

  /// What its tooltip says.
  static const tooltip = 'Open as graph';

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Clickable.hover(
      onTap: onTap,
      builder: (context, hovered) => SizedBox.square(
        dimension: size,
        child: Center(
          child: OpenOutIcon(
            size: 10,
            color: hovered ? FrameToggle.hoverColor : FrameToggle.color,
          ),
        ),
      ),
    ),
  );
}
