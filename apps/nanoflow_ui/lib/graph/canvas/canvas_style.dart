/// Colors and text of the graph canvas, from docs/design/graph.html and
/// task-graph.html; and the text measurer the layout lays them out with.
library;

import 'package:flutter/widgets.dart';

import '../../layout/layout.dart' show LabelKind;
import '../../theme.dart';
import 'canvas_marks.dart' show Tone;

/// The canvas's colors. Arrows, exits and input bars come in four tones
/// (`Tone` in canvas_marks.dart).
abstract final class CanvasColors {
  static const background = Color(0xFF27282C);
  static const gridDot = Color(0xFF3A3B41);

  /// The selected run's path; also the run legend.
  static const path = Color(0xFF9C8CFF);
  static const pathText = Color(0xFFBDB3FF);

  /// Arrows runs went along, not the selected run; and every arrow of
  /// `Current graph`.
  static const taken = Color(0xFF6B6C73);

  /// Arrows no run went along: darker.
  static const untaken = Color(0xFF4A4B52);
  static const untakenExit = Color(0xFF55565C);

  /// The color of arrows, their heads and input bars in [tone].
  static Color line(Tone tone) => switch (tone) {
    Tone.path => path,
    Tone.taken || Tone.plain => taken,
    Tone.untaken => untaken,
  };

  /// Labels and counters off the selected run's path.
  static const chipText = Color(0xFF9A9BA2);

  /// A tile: its fill and border, its icon, its name and place under it.
  static const tileFill = Color(0xFF323338);
  static const tileBorder = Color(0xFF55565C);
  static const icon = Color(0xFFC9CACF);
  static const name = Color(0xFFECECEE);
  static const place = Color(0xFF9A9BA2);

  /// The tiles stacked behind a call or copies.
  static const stackFill = Color(0xFF2C2D32);
  static const stackBorder = Color(0xFF55565C);

  /// The badge across the top of the stack of copies: `×n`.
  static const badgeFill = Color(0xFF3A3B41);
  static const badgeBorder = Color(0xFF4A4B52);
  static const badgeText = Color(0xFFD5D6DA);

  /// The dashed outline of the start and end markers, and their word.
  static const markerBorder = Color(0xFF5A5B62);
  static const markerText = Color(0xFFA7A8AE);

  /// The zoom buttons and the legend.
  static const panel = Color(0xFF202125);
  static const panelBorder = Color(0xFF34353A);
  static const buttonBorder = Color(0xFF3A3B41);
  static const buttonIcon = Color(0xFFD5D6DA);
  static const legendText = Color(0xFFA7A8AE);
}

/// The canvas's text. The layout measures with the same styles
/// ([measureLabel]), so what it keeps room for is what is drawn.
abstract final class CanvasText {
  static const _height = 1.3;

  static const _sans = TextStyle(
    inherit: false,
    fontFamily: AppText.sans,
    height: _height,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const _mono = TextStyle(
    inherit: false,
    fontFamily: AppText.mono,
    height: _height,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// A node's name under its tile; the selected step's node has it bold.
  static final name = _sans.copyWith(
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
  );

  /// A node's place in the code under its name.
  static final place = _mono.copyWith(fontSize: 10.5);

  /// The steps of a call or of a copy: `{ 3 }`.
  static final inside = _mono.copyWith(fontSize: 15, color: CanvasColors.icon);

  /// `×n` across the top of the stack of copies.
  static final badge = _mono.copyWith(
    fontSize: 10,
    color: CanvasColors.badgeText,
  );

  /// `start` and `end` in their markers.
  static final marker = _sans.copyWith(
    fontSize: 12,
    color: CanvasColors.markerText,
  );

  /// Exit labels and arrow counters on their chips.
  static final chip = _mono.copyWith(fontSize: 10);

  static final legend = _sans.copyWith(
    fontSize: 11,
    color: CanvasColors.legendText,
  );

  /// What the canvas says instead of a graph.
  static final placeholder = _sans.copyWith(
    fontSize: 13,
    color: CanvasColors.legendText,
  );

  /// How [kind] is drawn. A name is measured bold: the selected step's node
  /// has it so, and it must fit where the layout keeps room for it.
  static TextStyle of(LabelKind kind) => switch (kind) {
    LabelKind.exitLabel || LabelKind.counter => chip,
    LabelKind.nodeName => name.copyWith(fontWeight: FontWeight.w700),
    LabelKind.place => place,
  };
}

final Map<(String, LabelKind), double> _widths = {};

/// The width of [text] drawn as [kind] on the canvas: the layout's measurer.
double measureLabel(String text, LabelKind kind) =>
    _widths[(text, kind)] ??= () {
      final painter = TextPainter(
        text: TextSpan(text: text, style: CanvasText.of(kind)),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }();
