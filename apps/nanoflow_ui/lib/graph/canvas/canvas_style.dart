/// Colors and text of the graph canvas, from docs/design/graph.html and
/// task-graph.html; and the text measurer the layout lays them out with.
library;

import 'package:flutter/widgets.dart';

import '../../layout/layout.dart' show LabelKind;
import '../../theme.dart';
import 'canvas_marks.dart' show Tone;

/// The canvas's colors. Arrows, exits and input bars come in two tones
/// (`Tone` in canvas_marks.dart).
///
/// The background is darker than the mockups', so that tiles stand off it by
/// their fill and arrows and labels read at a glance: a tile's fill was all
/// but the canvas's own (1.17:1), and arrows were fainter than lines should be
/// (2.8:1). Its dots stay as faint as they were (1.34:1): something for the
/// eye to hold to, not to read.
abstract final class CanvasColors {
  static const background = Color(0xFF1C1D20);
  static const gridDot = Color(0xFF323338);

  /// Arrows, exits and input bars as the graph draws them: `Tone.plain`.
  static const plain = Color(0xFFA3A4AB);

  /// Arrows and input bars that lead to or from a node one copy shown has
  /// not reached: `Tone.untaken`, darker; and such exits.
  static const untaken = Color(0xFF55565D);
  static const untakenExit = Color(0xFF62636A);

  /// The color of arrows, their heads and input bars in [tone].
  static Color line(Tone tone) => switch (tone) {
    Tone.plain => plain,
    Tone.untaken => untaken,
  };

  /// Exit labels.
  static const chipText = Color(0xFFD5D6DA);

  /// A tile: its fill and border, its icon, its name and place under it.
  static const tileFill = Color(0xFF3A3B42);
  static const tileBorder = Color(0xFF7A7B83);
  static const icon = Color(0xFFE4E5E9);
  static const name = Color(0xFFECECEE);
  static const place = Color(0xFF6E6F76);

  /// A place under the pointer, a link into the code: as light as the exit
  /// labels.
  static const link = chipText;

  /// The tiles stacked behind copies.
  static const stackFill = Color(0xFF2E2F35);
  static const stackBorder = Color(0xFF6A6B73);

  /// The ring round the selected effect's node: 4 px of the accent at 38 %.
  static const ring = Color(0x619C8CFF);

  /// The badges over a tile: `×3` across the stack of copies, `2×` over a
  /// node entered more than once.
  static const badgeFill = Color(0xFF42434A);
  static const badgeBorder = Color(0xFF5E5F66);
  static const badgeText = Color(0xFFD5D6DA);

  /// The dashed outline of the start and end markers, and their word.
  static const markerBorder = Color(0xFF6E6F76);
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

  /// A node's name under its tile, in the weight of its tile's look.
  static final name = _sans.copyWith(
    fontSize: 12.5,
    fontWeight: FontWeight.w600,
  );

  /// A node's place in the code under its name.
  static final place = _mono.copyWith(fontSize: 10.5);

  /// The effects of a call or of a copy, small under its function icon:
  /// `{ 3 }`. A tile draws them in its look's colour (`TileLook.inside`).
  static final inside = _mono.copyWith(fontSize: 11, color: CanvasColors.icon);

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

  /// Exit labels on their chips.
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

  /// How [kind] is drawn. A name is measured in the heaviest weight a
  /// tile's look gives it ([name]'s), so it fits in every look.
  static TextStyle of(LabelKind kind) => switch (kind) {
    LabelKind.exitLabel => chip,
    LabelKind.nodeName => name,
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
