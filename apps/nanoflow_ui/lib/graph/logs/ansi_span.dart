import 'package:flutter/painting.dart';

import '../../state/ansi.dart';
import '../../theme.dart';

/// [runs] as text in their styles.
InlineSpan ansiSpan(List<AnsiRun> runs) => TextSpan(
  children: [
    for (final run in runs)
      TextSpan(text: run.text, style: ansiTextStyle(run.style)),
  ],
);

/// How text in [style] is drawn on the text area; `null` as the area's own.
TextStyle? ansiTextStyle(AnsiStyle style) {
  if (style == AnsiStyle.plain) return null;
  final foreground = style.foreground == null
      ? null
      : ansiColor(style.foreground!);
  final background = style.background == null
      ? null
      : ansiColor(style.background!);
  var (color, backgroundColor) = style.inverse
      ? (background ?? AppColors.textArea, foreground ?? AppColors.textAreaText)
      : (foreground, background);
  if (style.faint) {
    color = (color ?? AppColors.textAreaText).withValues(alpha: 0.6);
  }
  return TextStyle(
    color: color,
    backgroundColor: backgroundColor,
    fontWeight: style.bold ? FontWeight.w700 : null,
    fontStyle: style.italic ? FontStyle.italic : null,
    decoration: style.underline || style.crossedOut
        ? TextDecoration.combine([
            if (style.underline) TextDecoration.underline,
            if (style.crossedOut) TextDecoration.lineThrough,
          ])
        : null,
  );
}

/// [color] as shown: a named one in [AppColors.ansi], the others as xterm
/// has them.
Color ansiColor(AnsiColor color) => switch (color) {
  PaletteColor(:final index) when index < 16 => AppColors.ansi[index],
  // The 6×6×6 cube.
  PaletteColor(:final index) when index < 232 => Color.fromARGB(
    0xFF,
    _cubeLevel((index - 16) ~/ 36),
    _cubeLevel((index - 16) ~/ 6 % 6),
    _cubeLevel((index - 16) % 6),
  ),
  // 24 grays, from dark to light.
  PaletteColor(:final index) => Color.fromARGB(
    0xFF,
    8 + (index - 232) * 10,
    8 + (index - 232) * 10,
    8 + (index - 232) * 10,
  ),
  RgbColor(:final red, :final green, :final blue) => Color.fromARGB(
    0xFF,
    red,
    green,
    blue,
  ),
};

int _cubeLevel(int step) => step == 0 ? 0 : 55 + step * 40;
