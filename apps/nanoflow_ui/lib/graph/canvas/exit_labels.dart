import 'package:flutter/widgets.dart';

import '../../layout/layout.dart' as layout;
import 'canvas_marks.dart';
import 'canvas_style.dart';
import 'layout_geometry.dart';

/// An exit's label on its opaque chip.
final class ExitChip {
  const ExitChip(this.rect, this.text);

  final Rect rect;
  final String text;
}

/// Paints the exits of a layout (docs/ui-spec.md «Граф»): dots, capsules,
/// and the labels on chips of the canvas's color that arrows go behind.
/// Over the arrows, under the tiles: a tile covers the half of a dot on its
/// side, as in the mockups. Clicks go through it.
class ExitsPainter extends CustomPainter {
  ExitsPainter(this.graph, this.marks)
    : chips = List.unmodifiable(_chipsOf(graph));

  final layout.GraphLayout graph;
  final CanvasMarks marks;

  /// The labels, each where the layout put it.
  final List<ExitChip> chips;

  /// A dot's radius and the outline of the canvas's color round it.
  static const _dot = 5.5;
  static const _outline = 2.0;

  /// How far over a chip's bottom its text's baseline is.
  static const _baseline = 2.5;

  static List<ExitChip> _chipsOf(layout.GraphLayout graph) => [
    for (final exit in graph.exits)
      if ((exit.label, exit.labelRect) case (final label?, final rect?))
        ExitChip(rect.toRect(), label),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = CanvasColors.background;
    for (final exit in graph.exits) {
      // The arrows of a frame's start leave its side, where its bar is.
      if (graph.nodes[exit.node]?.port ?? false) continue;
      final tone = marks.exit(exit.node);
      final anchor = exit.anchor.toOffset();
      switch (exit.shape) {
        case layout.ExitShape.dot:
          _paintDot(canvas, anchor, tone, background);
        case layout.ExitShape.capsule:
          final handle = exit.handle.toRect();
          canvas
            ..drawRRect(
              RRect.fromRectAndRadius(
                handle.inflate(_outline / 2),
                const Radius.circular(_dot + _outline / 2),
              ),
              background,
            )
            ..drawRRect(
              RRect.fromRectAndRadius(
                handle.deflate(_outline / 2),
                const Radius.circular(_dot - _outline / 2),
              ),
              Paint()..color = _handleColor(tone),
            );
      }
    }
    final padding = graph.options.chipPadding;
    for (final chip in chips) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(chip.rect, const Radius.circular(3)),
        background,
      );
      final text = TextPainter(
        text: TextSpan(
          text: chip.text,
          style: CanvasText.chip.copyWith(color: CanvasColors.chipText),
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        maxLines: 1,
      )..layout();
      final baseline = text.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      text.paint(
        canvas,
        Offset(
          chip.rect.left + padding,
          chip.rect.bottom - _baseline - baseline,
        ),
      );
      text.dispose();
    }
  }

  void _paintDot(Canvas canvas, Offset at, Tone tone, Paint background) {
    canvas
      ..drawCircle(at, _dot + _outline / 2, background)
      ..drawCircle(
        at,
        _dot - _outline / 2,
        Paint()..color = _handleColor(tone),
      );
  }

  static Color _handleColor(Tone tone) => switch (tone) {
    Tone.plain => CanvasColors.plain,
    Tone.untaken => CanvasColors.untakenExit,
  };

  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(ExitsPainter old) =>
      old.graph != graph || old.marks != marks;
}
