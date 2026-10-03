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

  /// The selected way: `Tone.path`.
  static const path = Color(0xFF9C8CFF);
  static const pathText = Color(0xFFBDB3FF);

  /// Arrows steps went along, not the selected way; and every arrow of
  /// `Current graph`.
  static const taken = Color(0xFF6B6C73);

  /// Arrows no step went along: darker.
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

  /// The ring round the selected step's node: 4 px of the accent at 38 %.
  static const ring = Color(0x619C8CFF);

  /// The badges over a tile: `×3` across the stack of copies, `2×` over a
  /// node entered more than once.
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

  /// The badges over a tile: `×3`, `2×`.
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

  /// The title of a frame: `publish()`, `each pkg in packages`.
  static const frameTitle = TextStyle(
    inherit: false,
    fontFamily: AppText.sans,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: Color(0xFFD6D6DC),
  );

  /// Across from the title of a frame of copies: `×3 · in parallel`.
  static const frameCount = TextStyle(
    inherit: false,
    fontFamily: AppText.sans,
    fontSize: 12,
    height: 1.3,
    color: Color(0xFFA9A9B2),
  );

  /// Under a frame of copies: `done 1 of 3`.
  static const frameFooter = TextStyle(
    inherit: false,
    fontFamily: AppText.sans,
    fontSize: 10,
    height: 1.3,
    color: Color(0xFF8E8E96),
  );

  /// How [kind] is drawn. A name is measured bold: the selected step's node
  /// has it so, and it must fit where the layout keeps room for it.
  static TextStyle of(LabelKind kind) => switch (kind) {
    LabelKind.exitLabel || LabelKind.counter => chip,
    LabelKind.nodeName => name.copyWith(fontWeight: FontWeight.w700),
    LabelKind.place => place,
  };
}

final Map<(String, TextStyle), double> _widths = {};

/// The width of [text] drawn in [style] on one line, measured once.
double measureText(String text, TextStyle style) =>
    _widths[(text, style)] ??= () {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }();

/// The width of [text] drawn as [kind] on the canvas: the layout's measurer.
double measureLabel(String text, LabelKind kind) =>
    measureText(text, CanvasText.of(kind));
