import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/state/ansi.dart';

void main() {
  const red = AnsiStyle(foreground: PaletteColor(1));

  List<AnsiRun> runsOf(String line, [AnsiStyle style = AnsiStyle.plain]) =>
      ansiRuns(line, style).runs;

  group('the runs of a line', () {
    test('a line without escapes is one run in the style it starts in', () {
      expect(runsOf('plain text'), [
        (text: 'plain text', style: AnsiStyle.plain),
      ]);
      expect(runsOf('still red', red), [(text: 'still red', style: red)]);
      expect(runsOf(''), isEmpty);
    });

    test('SGR sets the style of what follows, and 0 resets it', () {
      expect(runsOf('a \x1b[31mred\x1b[0m b'), [
        (text: 'a ', style: AnsiStyle.plain),
        (text: 'red', style: red),
        (text: ' b', style: AnsiStyle.plain),
      ]);
      expect(runsOf('\x1b[31mred\x1b[m plain'), [
        (text: 'red', style: red),
        (text: ' plain', style: AnsiStyle.plain),
      ]);
    });

    test('codes add up, in one sequence or in several', () {
      const style = AnsiStyle(
        foreground: PaletteColor(2),
        background: PaletteColor(4),
        bold: true,
        faint: true,
        italic: true,
        underline: true,
        inverse: true,
        crossedOut: true,
      );
      expect(runsOf('\x1b[1;2;3;4;7;9;32;44mx'), [(text: 'x', style: style)]);
      expect(
        runsOf(
          '\x1b[1m\x1b[2m\x1b[3m\x1b[4m\x1b[7m\x1b[9m\x1b[32m'
          '\x1b[44mx',
        ),
        [(text: 'x', style: style)],
      );
    });

    test('each attribute has its own code that turns it off', () {
      const all = AnsiStyle(
        foreground: PaletteColor(2),
        background: PaletteColor(4),
        bold: true,
        faint: true,
        italic: true,
        underline: true,
        inverse: true,
        crossedOut: true,
      );

      /// The attributes on in [all] after [codes].
      Set<String> after(String codes) {
        final style = ansiRuns('\x1b[${codes}m', all).end;
        return {
          if (style.bold) 'bold',
          if (style.faint) 'faint',
          if (style.italic) 'italic',
          if (style.underline) 'underline',
          if (style.inverse) 'inverse',
          if (style.crossedOut) 'crossedOut',
        };
      }

      const others = ['italic', 'underline', 'inverse', 'crossedOut'];
      expect(after('22'), {...others});
      expect(after('23'), {'bold', 'faint', ...others}..remove('italic'));
      expect(after('24'), {'bold', 'faint', ...others}..remove('underline'));
      expect(after('27'), {'bold', 'faint', ...others}..remove('inverse'));
      expect(after('29'), {'bold', 'faint', ...others}..remove('crossedOut'));
      expect(ansiRuns('\x1b[39m', all).end.foreground, isNull);
      expect(ansiRuns('\x1b[49m', all).end.background, isNull);
      expect(ansiRuns('\x1b[39;49;22;23;24;27;29m', all).end, AnsiStyle.plain);
    });

    test('bright colors are the second eight of the palette', () {
      expect(
        ansiRuns('\x1b[91;102m').end,
        const AnsiStyle(
          foreground: PaletteColor(9),
          background: PaletteColor(10),
        ),
      );
      expect(
        ansiRuns('\x1b[30;47m').end,
        const AnsiStyle(
          foreground: PaletteColor(0),
          background: PaletteColor(7),
        ),
      );
    });

    test('256 colors and RGB, with semicolons or colons', () {
      const rgb = RgbColor(255, 128, 0);
      for (final (codes, style) in [
        ('38;5;208', const AnsiStyle(foreground: PaletteColor(208))),
        ('48;5;17', const AnsiStyle(background: PaletteColor(17))),
        ('38;2;255;128;0', const AnsiStyle(foreground: rgb)),
        ('48;2;255;128;0', const AnsiStyle(background: rgb)),
        ('38:5:208', const AnsiStyle(foreground: PaletteColor(208))),
        ('38:2:255:128:0', const AnsiStyle(foreground: rgb)),
        ('38:2::255:128:0', const AnsiStyle(foreground: rgb)),
        (
          '1;38;5;208;4',
          const AnsiStyle(
            foreground: PaletteColor(208),
            bold: true,
            underline: true,
          ),
        ),
      ]) {
        expect(ansiRuns('\x1b[${codes}m').end, style, reason: codes);
      }
    });

    test('codes it does not know, and a color out of range, change nothing, '
        'and what they take is not read as codes', () {
      expect(ansiRuns('\x1b[5;53;31m').end, red);
      expect(ansiRuns('\x1b[38;5;300;1m').end, const AnsiStyle(bold: true));
      // The color of the underline is not shown: its 31 is no foreground.
      expect(ansiRuns('\x1b[58;5;31m').end, AnsiStyle.plain);
      expect(ansiRuns('\x1b[58;2;31;31;31m').end, AnsiStyle.plain);
      expect(
        ansiRuns(
          '\x1b[4:0m',
          const AnsiStyle(foreground: PaletteColor(1), underline: true),
        ).end,
        red,
      );
      expect(ansiRuns('\x1b[4:3m').end, const AnsiStyle(underline: true));
    });

    test('other escape sequences are dropped', () {
      for (final line in [
        // Erase the line, move the cursor.
        'a\x1b[2Kb', 'a\x1b[1;5Hb', 'a\x1b[?25lb',
        // A hyperlink, a window title.
        'a\x1b]8;;https://x.dev\x1b\\b\x1b]8;;\x1b\\',
        'a\x1b]0;title\x07b',
        // Save the cursor, choose a charset.
        'a\x1b7b', 'a\x1b(Bb',
      ]) {
        expect(runsOf(line), [
          (text: 'ab', style: AnsiStyle.plain),
        ], reason: line.replaceAll('\x1b', r'\e'));
      }
    });

    test('an escape before a byte that begins no sequence is dropped '
        'alone', () {
      expect(runsOf('a\x1b\x1b[31mb'), [
        (text: 'a', style: AnsiStyle.plain),
        (text: 'b', style: red),
      ]);
      expect(runsOf('a\x1bé'), [(text: 'aé', style: AnsiStyle.plain)]);
    });

    test('an escape sequence the line ends in before it is complete is '
        'dropped', () {
      expect(runsOf('a\x1b[31'), [(text: 'a', style: AnsiStyle.plain)]);
      expect(runsOf('a\x1b]8;;https://x.dev'), [
        (text: 'a', style: AnsiStyle.plain),
      ]);
      expect(runsOf('a\x1b'), [(text: 'a', style: AnsiStyle.plain)]);
    });

    test('the style it ends in goes on to the next line', () {
      final first = ansiRuns('\x1b[31mred');
      expect(first.end, red);
      expect(ansiRuns('more', first.end).runs, [(text: 'more', style: red)]);
      expect(ansiRuns('more\x1b[0m', first.end).end, AnsiStyle.plain);
    });
  });

  test('a style codes leave as it was is the same, and plain is plain', () {
    expect(ansiRuns('\x1b[1m\x1b[0m').end, same(AnsiStyle.plain));
    const bold = AnsiStyle(bold: true);
    expect(ansiRuns('a\x1b[1mb\x1b[Kc', bold).end, same(bold));
  });

  test('the width of a line is that of its text without escapes', () {
    expect(ansiWidth('a \x1b[1;31mred\x1b[0m b\x1b[K'), (
      width: 7,
      end: AnsiStyle.plain,
    ));
    expect(ansiWidth('\x1b[31mred'), (width: 3, end: red));
    expect(ansiWidth('plain'), (width: 5, end: AnsiStyle.plain));
  });

  test('a line without its escapes', () {
    expect(withoutEscapes('a \x1b[1;31mred\x1b[0m b\x1b[K'), 'a red b');
    expect(withoutEscapes('plain'), 'plain');
  });
}
