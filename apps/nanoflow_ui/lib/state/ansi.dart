/// The colors and the weight of a log's text, as the escape sequences of a
/// terminal set them (docs/ui-spec.md «Logs»: «Цвета ANSI»): SGR,
/// `ESC [ … m`, styles the text after it, on to the next lines, until another
/// one changes or resets it; every other escape sequence is dropped. Pure.
library;

import 'dart:math' as math;

/// A color of text: one of the 256 of a terminal's palette, or red, green
/// and blue.
sealed class AnsiColor {
  const AnsiColor();
}

/// The color [index] of a terminal's palette: the 16 named ones first —
/// black, red, green, yellow, blue, magenta, cyan, white, then their bright
/// kind — then a 6×6×6 cube of colors and 24 grays.
final class PaletteColor extends AnsiColor {
  const PaletteColor(this.index);

  final int index;

  @override
  bool operator ==(Object other) =>
      other is PaletteColor && other.index == index;

  @override
  int get hashCode => index.hashCode;

  @override
  String toString() => 'PaletteColor($index)';
}

/// A color by its red, green and blue, from 0 to 255.
final class RgbColor extends AnsiColor {
  const RgbColor(this.red, this.green, this.blue);

  final int red;
  final int green;
  final int blue;

  @override
  bool operator ==(Object other) =>
      other is RgbColor &&
      other.red == red &&
      other.green == green &&
      other.blue == blue;

  @override
  int get hashCode => Object.hash(red, green, blue);

  @override
  String toString() => 'RgbColor($red, $green, $blue)';
}

/// How text is drawn; `null` colors are those of the text area.
final class AnsiStyle {
  const AnsiStyle({
    this.foreground,
    this.background,
    this.bold = false,
    this.faint = false,
    this.italic = false,
    this.underline = false,
    this.inverse = false,
    this.crossedOut = false,
  });

  /// The text area's own.
  static const plain = AnsiStyle();

  final AnsiColor? foreground;
  final AnsiColor? background;
  final bool bold;
  final bool faint;
  final bool italic;
  final bool underline;

  /// The foreground and the background change places.
  final bool inverse;
  final bool crossedOut;

  @override
  bool operator ==(Object other) =>
      other is AnsiStyle &&
      other.foreground == foreground &&
      other.background == background &&
      other.bold == bold &&
      other.faint == faint &&
      other.italic == italic &&
      other.underline == underline &&
      other.inverse == inverse &&
      other.crossedOut == crossedOut;

  @override
  int get hashCode => Object.hash(
    foreground,
    background,
    bold,
    faint,
    italic,
    underline,
    inverse,
    crossedOut,
  );

  @override
  String toString() {
    final parts = [
      if (foreground != null) 'foreground: $foreground',
      if (background != null) 'background: $background',
      if (bold) 'bold',
      if (faint) 'faint',
      if (italic) 'italic',
      if (underline) 'underline',
      if (inverse) 'inverse',
      if (crossedOut) 'crossedOut',
    ];
    return 'AnsiStyle(${parts.join(', ')})';
  }
}

/// Text in one style.
typedef AnsiRun = ({String text, AnsiStyle style});

/// The text of [line] in its styles, from [style] at its start: the runs of
/// the text, its escape sequences gone, and the style the line ends in — that
/// of the next line's start.
///
/// An escape sequence that the line ends in before it is complete is dropped.
({List<AnsiRun> runs, AnsiStyle end}) ansiRuns(
  String line, [
  AnsiStyle style = AnsiStyle.plain,
]) {
  final runs = <AnsiRun>[];
  final end = _read(line, style, (from, to, style) {
    final text = line.substring(from, to);
    if (runs.lastOrNull case (text: final last, style: final same)
        when same == style) {
      runs.last = (text: '$last$text', style: style);
    } else {
      runs.add((text: text, style: style));
    }
  });
  return (runs: runs, end: end);
}

/// How many characters [line] shows, and the style it ends in, as
/// [ansiRuns] has them; without building the runs, for every line of a log
/// as it comes.
({int width, AnsiStyle end}) ansiWidth(
  String line, [
  AnsiStyle style = AnsiStyle.plain,
]) {
  var width = line.length;
  var i = line.indexOf(_escape);
  while (i >= 0) {
    final (:end, :codes) = _sequenceAt(line, i);
    if (codes >= 0) style = _withCodes(style, line, codes, end - 1);
    width -= end - i;
    i = line.indexOf(_escape, end);
  }
  return (width: width, end: style);
}

/// [line] without its escape sequences.
String withoutEscapes(String line) {
  if (!line.contains(_escape)) return line;
  final text = StringBuffer();
  _read(line, AnsiStyle.plain, (from, to, _) {
    text.write(line.substring(from, to));
  });
  return text.toString();
}

/// Reads [line] from [style]: gives [text] each stretch of text between its
/// escape sequences, by where it begins and ends, in its style; returns the
/// style the line ends in.
AnsiStyle _read(
  String line,
  AnsiStyle style,
  void Function(int from, int to, AnsiStyle style) text,
) {
  var i = 0;
  while (i < line.length) {
    final next = line.indexOf(_escape, i);
    final to = next < 0 ? line.length : next;
    if (to > i) text(i, to, style);
    if (next < 0) break;
    final (:end, :codes) = _sequenceAt(line, next);
    if (codes >= 0) style = _withCodes(style, line, codes, end - 1);
    i = end;
  }
  return style;
}

const _escape = '\x1b';

/// The escape sequence at [start] of [line]: where it ends, and where the
/// codes of SGR begin — they end before its `m` — or -1 for any other
/// sequence.
({int end, int codes}) _sequenceAt(String line, int start) {
  var i = start + 1;
  if (i == line.length) return (end: i, codes: -1);
  final kind = line.codeUnitAt(i++);
  switch (kind) {
    // CSI: parameters, then intermediates, then the final byte.
    case 0x5B: // [
      final from = i;
      while (i < line.length && _within(line.codeUnitAt(i), 0x30, 0x3F)) {
        i++;
      }
      final intermediates = i;
      while (i < line.length && _within(line.codeUnitAt(i), 0x20, 0x2F)) {
        i++;
      }
      if (i == line.length || !_within(line.codeUnitAt(i), 0x40, 0x7E)) {
        // Broken off: what follows is text again.
        return (end: i, codes: -1);
      }
      final sgr =
          line.codeUnitAt(i) == 0x6D && // m
          i == intermediates &&
          // Not a private sequence: `ESC [ > 4 ; 2 m`.
          (from == i || !_within(line.codeUnitAt(from), 0x3C, 0x3F));
      return (end: i + 1, codes: sgr ? from : -1);
    // OSC, DCS, SOS, PM, APC: a string up to ST, `ESC \`, or BEL.
    case 0x5D || 0x50 || 0x58 || 0x5E || 0x5F: // ] P X ^ _
      while (i < line.length) {
        final char = line.codeUnitAt(i);
        if (char == 0x07) return (end: i + 1, codes: -1);
        if (char == 0x1B && i + 1 < line.length && line[i + 1] == r'\') {
          return (end: i + 2, codes: -1);
        }
        i++;
      }
      return (end: i, codes: -1);
    // Intermediates, then the final byte: `ESC ( B`.
    case final char when _within(char, 0x20, 0x2F):
      while (i < line.length && _within(line.codeUnitAt(i), 0x20, 0x2F)) {
        i++;
      }
      if (i < line.length && _within(line.codeUnitAt(i), 0x30, 0x7E)) i++;
      return (end: i, codes: -1);
    // A sequence of one byte: `ESC 7`.
    case final char when _within(char, 0x30, 0x7E):
      return (end: i, codes: -1);
    // A byte that begins no sequence: only the escape is dropped.
    default:
      return (end: i - 1, codes: -1);
  }
}

bool _within(int char, int from, int to) => char >= from && char <= to;

/// The colors of the palette, one object each: a log's lines share them.
final _palette = List.generate(256, PaletteColor.new, growable: false);

/// The numbers of the SGR being read — kept rather than made anew for each,
/// as a log has an SGR or more on most lines: all of them in order, -1 for
/// one left empty, and where each parameter's begin, its sub-parameters
/// after `:` following its first.
final _numbers = <int>[];
final _parameters = <int>[];

/// Reads the numbers of the SGR codes from [from] to [to] of [line] into
/// [_numbers] and [_parameters].
void _readNumbers(String line, int from, int to) {
  _numbers.clear();
  _parameters
    ..clear()
    ..add(0);
  var number = -1;
  for (var i = from; i < to; i++) {
    final char = line.codeUnitAt(i);
    if (char == 0x3A || char == 0x3B) {
      // : ;
      _numbers.add(number);
      number = -1;
      if (char == 0x3B) _parameters.add(_numbers.length);
    } else if (_within(char, 0x30, 0x39) && number < 100000) {
      number = (number < 0 ? 0 : number) * 10 + char - 0x30;
    }
  }
  _numbers.add(number);
}

/// [style] after the SGR codes from [from] to [to] of [line]: `1;31`,
/// `38;5;208`, `38:2::255:128:0`. Codes it does not know change nothing. A
/// style the codes leave as it was is [style] itself, and the plain one
/// [AnsiStyle.plain]: a log's lines share their styles rather than each
/// holding its own.
AnsiStyle _withCodes(AnsiStyle style, String line, int from, int to) {
  var foreground = style.foreground;
  var background = style.background;
  var bold = style.bold;
  var faint = style.faint;
  var italic = style.italic;
  var underline = style.underline;
  var inverse = style.inverse;
  var crossedOut = style.crossedOut;

  _readNumbers(line, from, to);
  for (var p = 0; p < _parameters.length; p++) {
    final first = _parameters[p];
    final end = p + 1 < _parameters.length
        ? _parameters[p + 1]
        : _numbers.length;
    // An empty code is 0.
    final code = math.max(_numbers[first], 0);
    switch (code) {
      case 0:
        foreground = background = null;
        bold = faint = italic = underline = inverse = crossedOut = false;
      case 1:
        bold = true;
      case 2:
        faint = true;
      case 3:
        italic = true;
      case 4:
        // `4:0` is no underline; `4:3`, a curly one.
        underline = end - first < 2 || _numbers[first + 1] != 0;
      case 7:
        inverse = true;
      case 9:
        crossedOut = true;
      case 22:
        bold = faint = false;
      case 23:
        italic = false;
      case 24:
        underline = false;
      case 27:
        inverse = false;
      case 29:
        crossedOut = false;
      case >= 30 && <= 37:
        foreground = _palette[code - 30];
      case 39:
        foreground = null;
      case >= 40 && <= 47:
        background = _palette[code - 40];
      case 49:
        background = null;
      case >= 90 && <= 97:
        foreground = _palette[code - 90 + 8];
      case >= 100 && <= 107:
        background = _palette[code - 100 + 8];
      // A color by its number or by red, green and blue: 58 is that of the
      // underline, which is not shown, but its numbers are not codes.
      case 38 || 48 || 58:
        final colons = end - first > 1;
        final (:color, :parameters) = colons
            ? _color(first + 1, end, colons: true)
            : _color(p + 1, _parameters.length, colons: false);
        p += parameters;
        if (color == null) break;
        if (code == 38) foreground = color;
        if (code == 48) background = color;
    }
  }
  if (foreground == style.foreground &&
      background == style.background &&
      bold == style.bold &&
      faint == style.faint &&
      italic == style.italic &&
      underline == style.underline &&
      inverse == style.inverse &&
      crossedOut == style.crossedOut) {
    return style;
  }
  if (foreground == null &&
      background == null &&
      !bold &&
      !faint &&
      !italic &&
      !underline &&
      !inverse &&
      !crossedOut) {
    return AnsiStyle.plain;
  }
  return AnsiStyle(
    foreground: foreground,
    background: background,
    bold: bold,
    faint: faint,
    italic: italic,
    underline: underline,
    inverse: inverse,
    crossedOut: crossedOut,
  );
}

/// The color the numbers after 38 or 48 name — `5;208`, `2;255;128;0`; with
/// [colons], `2::255:128:0` too, its color space left empty — `null` when
/// they name none; and how many parameters they take. With [colons] the
/// numbers are the sub-parameters [from] to [to] of [_numbers], and they take
/// no parameters; without, the first numbers of the parameters [from] to
/// [to] of [_parameters].
({AnsiColor? color, int parameters}) _color(
  int from,
  int to, {
  required bool colons,
}) {
  int at(int i) => from + i >= to
      ? -1
      : colons
      ? _numbers[from + i]
      : _numbers[_parameters[from + i]];
  bool byte(int n) => n >= 0 && n <= 255;
  switch (at(0)) {
    case 5:
      final index = at(1);
      return (
        color: byte(index) ? _palette[index] : null,
        parameters: colons ? 0 : 2,
      );
    case 2:
      final i = colons && to - from > 4 ? 2 : 1;
      final (red, green, blue) = (at(i), at(i + 1), at(i + 2));
      return (
        color: byte(red) && byte(green) && byte(blue)
            ? RgbColor(red, green, blue)
            : null,
        parameters: colons ? 0 : 4,
      );
  }
  return (color: null, parameters: 0);
}
