import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/graph/logs/ansi_span.dart';
import 'package:nanoflow_ui/state/ansi.dart';
import 'package:nanoflow_ui/theme.dart';

void main() {
  group('the color of', () {
    test('a named color is the app\'s', () {
      expect(AppColors.ansi, hasLength(16));
      for (var i = 0; i < 16; i++) {
        expect(ansiColor(PaletteColor(i)), AppColors.ansi[i], reason: '$i');
      }
    });

    test('the cube and the grays are those of xterm', () {
      expect(ansiColor(const PaletteColor(16)), const Color(0xFF000000));
      expect(ansiColor(const PaletteColor(196)), const Color(0xFFFF0000));
      expect(ansiColor(const PaletteColor(208)), const Color(0xFFFF8700));
      expect(ansiColor(const PaletteColor(231)), const Color(0xFFFFFFFF));
      expect(ansiColor(const PaletteColor(232)), const Color(0xFF080808));
      expect(ansiColor(const PaletteColor(255)), const Color(0xFFEEEEEE));
    });

    test('red, green and blue is that color', () {
      expect(ansiColor(const RgbColor(255, 128, 0)), const Color(0xFFFF8000));
    });
  });

  group('the text style of', () {
    test('plain text is the text area\'s', () {
      expect(ansiTextStyle(AnsiStyle.plain), isNull);
    });

    test('colors are the foreground and the background', () {
      final style = ansiTextStyle(
        const AnsiStyle(
          foreground: PaletteColor(1),
          background: PaletteColor(4),
        ),
      )!;
      expect(style.color, AppColors.ansi[1]);
      expect(style.backgroundColor, AppColors.ansi[4]);
    });

    test('bold, italic, underline and crossed out', () {
      final style = ansiTextStyle(
        const AnsiStyle(
          bold: true,
          italic: true,
          underline: true,
          crossedOut: true,
        ),
      )!;
      expect(style.fontWeight, FontWeight.w700);
      expect(style.fontStyle, FontStyle.italic);
      expect(
        style.decoration,
        TextDecoration.combine([
          TextDecoration.underline,
          TextDecoration.lineThrough,
        ]),
      );
    });

    test('faint text is its color, dimmed', () {
      expect(
        ansiTextStyle(const AnsiStyle(faint: true))!.color,
        AppColors.textAreaText.withValues(alpha: 0.6),
      );
      expect(
        ansiTextStyle(
          const AnsiStyle(foreground: PaletteColor(2), faint: true),
        )!.color,
        AppColors.ansi[2].withValues(alpha: 0.6),
      );
    });

    test('inverse text swaps the colors, those of the text area too', () {
      final plain = ansiTextStyle(const AnsiStyle(inverse: true))!;
      expect(plain.color, AppColors.textArea);
      expect(plain.backgroundColor, AppColors.textAreaText);

      final red = ansiTextStyle(
        const AnsiStyle(foreground: PaletteColor(1), inverse: true),
      )!;
      expect(red.color, AppColors.textArea);
      expect(red.backgroundColor, AppColors.ansi[1]);
    });
  });

  test('runs are spans in their styles', () {
    final span = ansiSpan([
      (text: 'a ', style: AnsiStyle.plain),
      (text: 'red', style: const AnsiStyle(foreground: PaletteColor(1))),
    ]);
    expect(span.toPlainText(), 'a red');
    final children = (span as TextSpan).children!.cast<TextSpan>();
    expect(children.map((child) => child.text), ['a ', 'red']);
    expect(children.first.style, isNull);
    expect(children.last.style!.color, AppColors.ansi[1]);
  });
}
