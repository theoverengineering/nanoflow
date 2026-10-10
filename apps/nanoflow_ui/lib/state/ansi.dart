/// The colors and the weight of a log's text, as the escape sequences of a
/// terminal set them (docs/ui-spec.md «Logs»: «Цвета ANSI»): SGR,
/// `ESC [ … m`, styles the text after it, on to the next lines, until another
/// one changes or resets it; every other escape sequence is dropped. Pure.
library;

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
  var width = 0;
  final end = _read(line, style, (from, to, _) => width += to - from);
  return (width: width, end: end);
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
    final sequence = _sequenceAt(line, next);
    if (sequence.sgr case final codes?) style = _withCodes(style, codes);
    i = sequence.end;
  }
  return style;
}

const _escape = '\x1b';

/// The escape sequence at [start] of [line]: where it ends, and the codes of
/// SGR, `null` for any other sequence.
({int end, String? sgr}) _sequenceAt(String line, int start) {
  var i = start + 1;
  if (i == line.length) return (end: i, sgr: null);
  final kind = line.codeUnitAt(i++);
  switch (kind) {
    // CSI: parameters, then intermediates, then the final byte.
    case 0x5B: // [
      final from = i;
      while (i < line.length && _within(line.codeUnitAt(i), 0x30, 0x3F)) {
        i++;
      }
      final parameters = line.substring(from, i);
      final intermediates = i;
      while (i < line.length && _within(line.codeUnitAt(i), 0x20, 0x2F)) {
        i++;
      }
      if (i == line.length || !_within(line.codeUnitAt(i), 0x40, 0x7E)) {
        // Broken off: what follows is text again.
        return (end: i, sgr: null);
      }
      final sgr =
          line.codeUnitAt(i) == 0x6D && // m
          i == intermediates &&
          // Not a private sequence: `ESC [ > 4 ; 2 m`.
          (parameters.isEmpty ||
              !_within(parameters.codeUnitAt(0), 0x3C, 0x3F));
      return (end: i + 1, sgr: sgr ? parameters : null);
    // OSC, DCS, SOS, PM, APC: a string up to ST, `ESC \`, or BEL.
    case 0x5D || 0x50 || 0x58 || 0x5E || 0x5F: // ] P X ^ _
      while (i < line.length) {
        final char = line.codeUnitAt(i);
        if (char == 0x07) return (end: i + 1, sgr: null);
        if (char == 0x1B && i + 1 < line.length && line[i + 1] == r'\') {
          return (end: i + 2, sgr: null);
        }
        i++;
      }
      return (end: i, sgr: null);
    // Intermediates, then the final byte: `ESC ( B`.
    case final char when _within(char, 0x20, 0x2F):
      while (i < line.length && _within(line.codeUnitAt(i), 0x20, 0x2F)) {
        i++;
      }
      if (i < line.length && _within(line.codeUnitAt(i), 0x30, 0x7E)) i++;
      return (end: i, sgr: null);
    // A sequence of one byte: `ESC 7`.
    case final char when _within(char, 0x30, 0x7E):
      return (end: i, sgr: null);
    // A byte that begins no sequence: only the escape is dropped.
    default:
      return (end: i - 1, sgr: null);
  }
}

bool _within(int char, int from, int to) => char >= from && char <= to;

/// [style] after the SGR [codes]: `1;31`, `38;5;208`, `38:2::255:128:0`.
/// Codes it does not know change nothing. A style the codes leave as it was
/// is [style] itself, and the plain one [AnsiStyle.plain]: a log's lines
/// share their styles rather than each holding its own.
AnsiStyle _withCodes(AnsiStyle style, String codes) {
  var foreground = style.foreground;
  var background = style.background;
  var bold = style.bold;
  var faint = style.faint;
  var italic = style.italic;
  var underline = style.underline;
  var inverse = style.inverse;
  var crossedOut = style.crossedOut;

  final parameters = codes.split(';');
  for (var i = 0; i < parameters.length; i++) {
    final parts = parameters[i].split(':');
    final code = int.tryParse(parts.first) ?? 0;
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
        underline = parts.length < 2 || parts[1] != '0';
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
        foreground = PaletteColor(code - 30);
      case 39:
        foreground = null;
      case >= 40 && <= 47:
        background = PaletteColor(code - 40);
      case 49:
        background = null;
      case >= 90 && <= 97:
        foreground = PaletteColor(code - 90 + 8);
      case >= 100 && <= 107:
        background = PaletteColor(code - 100 + 8);
      // A color by its number or by red, green and blue: 58 is that of the
      // underline, which is not shown, but its numbers are not codes.
      case 38 || 48 || 58:
        final AnsiColor? color;
        if (parts.length > 1) {
          color = _color(parts.sublist(1), colons: true);
        } else {
          final rest = parameters.sublist(i + 1);
          color = _color(rest, colons: false);
          i += switch (rest.firstOrNull) {
            '5' => 2,
            '2' => 4,
            _ => 0,
          };
        }
        if (color == null) break;
        if (code == 38) foreground = color;
        if (code == 48) background = color;
    }
  }
  final after = AnsiStyle(
    foreground: foreground,
    background: background,
    bold: bold,
    faint: faint,
    italic: italic,
    underline: underline,
    inverse: inverse,
    crossedOut: crossedOut,
  );
  return after == style
      ? style
      : after == AnsiStyle.plain
      ? AnsiStyle.plain
      : after;
}

/// The color [numbers] after 38 or 48 name: `5;208`, `2;255;128;0`; with
/// [colons], `2::255:128:0` too, its color space left empty. `null` when they
/// name none.
AnsiColor? _color(List<String> numbers, {required bool colons}) {
  int? at(int i) => i < numbers.length ? int.tryParse(numbers[i]) : null;
  bool byte(int? n) => n != null && n >= 0 && n <= 255;
  switch (numbers.firstOrNull) {
    case '5':
      final index = at(1);
      return byte(index) ? PaletteColor(index!) : null;
    case '2':
      final from = colons && numbers.length > 4 ? 2 : 1;
      final (red, green, blue) = (at(from), at(from + 1), at(from + 2));
      return byte(red) && byte(green) && byte(blue)
          ? RgbColor(red!, green!, blue!)
          : null;
  }
  return null;
}
