import 'package:flutter/widgets.dart';

import '../../layout/layout.dart' as layout;
import 'canvas_marks.dart';
import 'canvas_style.dart';
import 'layout_geometry.dart';

/// A key or a counter on its opaque chip.
final class ExitChip {
  const ExitChip(this.rect, this.text, this.color);

  final Rect rect;
  final String text;
  final Color color;
}

/// Paints the exits of a layout (docs/ui-spec.md «Граф»): dots, capsules,
/// stubs with their cross bars, and the keys and counters on chips of the
/// canvas's color that arrows go behind. Over the arrows, under the tiles:
/// a tile covers the half of a dot on its side, as in the mockups.
class ExitsPainter extends CustomPainter {
  ExitsPainter(this.graph, this.marks)
    : chips = List.unmodifiable(_chipsOf(graph, marks));

  final layout.GraphLayout graph;
  final CanvasMarks marks;

  /// The keys and counters, each where the layout put it.
  final List<ExitChip> chips;

  /// A dot's radius and the outline of the canvas's color round it.
  static const _dot = 5.5;
  static const _outline = 2.0;

  static const _stubWidth = 1.6;
  static const _barWidth = 2.4;
  static const _barHalf = 6.0;

  /// How far over a chip's bottom its text's baseline is.
  static const _baseline = 2.5;

  static List<ExitChip> _chipsOf(layout.GraphLayout graph, CanvasMarks marks) {
    final options = graph.options;
    final chips = <ExitChip>[];
    for (final exit in graph.exits) {
      final color = marks.exit(exit.node, exit.index) == Tone.path
          ? CanvasColors.pathText
          : CanvasColors.chipText;
      final label = exit.label;
      final labelRect = exit.labelRect;
      if (label != null && labelRect != null) {
        chips.add(ExitChip(labelRect.toRect(), label, color));
      }
      final counter = marks.counter(exit.node, exit.index);
      if (counter != null) {
        final width =
            options.measure(counter, layout.LabelKind.counter) +
            2 * options.chipPadding;
        chips.add(
          ExitChip(
            Rect.fromLTWH(
              exit.counterAt.x,
              exit.counterAt.y,
              width,
              options.chipHeight,
            ),
            counter,
            color,
          ),
        );
      }
    }
    return chips;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = CanvasColors.background;
    for (final exit in graph.exits) {
      final tone = marks.exit(exit.node, exit.index);
      final anchor = exit.anchor.toOffset();
      switch (exit.shape) {
        case layout.ExitShape.stub:
          final end = Offset(exit.stubEnd!, anchor.dy);
          canvas
            ..drawLine(
              anchor,
              end,
              Paint()
                ..color = _stubColor(tone)
                ..strokeWidth = _stubWidth,
            )
            ..drawLine(
              end.translate(0, -_barHalf),
              end.translate(0, _barHalf),
              Paint()
                ..color = _stubBarColor(tone)
                ..strokeWidth = _barWidth
                ..strokeCap = StrokeCap.round,
            );
          _paintDot(canvas, anchor, tone, background);
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
          style: CanvasText.chip.copyWith(color: chip.color),
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
    Tone.path => CanvasColors.path,
    Tone.taken || Tone.plain => CanvasColors.taken,
    Tone.untaken => CanvasColors.untakenExit,
  };

  static Color _stubColor(Tone tone) => switch (tone) {
    Tone.untaken => CanvasColors.stub,
    _ => _handleColor(tone),
  };

  static Color _stubBarColor(Tone tone) => switch (tone) {
    Tone.untaken => CanvasColors.stubBar,
    _ => _handleColor(tone),
  };

  @override
  bool shouldRepaint(ExitsPainter old) =>
      old.graph != graph || old.marks != marks;
}
