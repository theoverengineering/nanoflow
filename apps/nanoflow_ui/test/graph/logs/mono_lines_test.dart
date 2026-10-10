import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/graph/logs/mono_lines.dart';
import 'package:nanoflow_ui/state/ansi.dart';

void main() {
  const red = AnsiStyle(foreground: PaletteColor(1));

  List<AnsiRun> shown(String line, {bool whole = false}) =>
      shownRuns(ansiRuns(line).runs, whole: whole);

  group('a line as shown', () {
    test('drops a carriage return at its end, escapes after it too', () {
      expect(shownLine('a\r', whole: false), 'a');
      expect(shown('\x1b[31ma\r\x1b[0m'), [(text: 'a', style: red)]);
      expect(shown('\x1b[31ma\x1b[0m\r'), [(text: 'a', style: red)]);
    });

    test('puts tabs at every 8th column of the text shown', () {
      expect(shownLine('ab\tc', whole: false), 'ab      c');
      expect(shown('\x1b[31mab\x1b[0m\tc'), [
        (text: 'ab', style: red),
        (text: '      c', style: AnsiStyle.plain),
      ]);
    });

    test('is cut at the characters shown, and whole is not', () {
      final long = '\x1b[31m${'x' * 1500}\x1b[0m${'y' * 1000}';
      expect(shown(long), [
        (text: 'x' * 1500, style: red),
        (text: 'y' * (previewLineLength - 1500), style: AnsiStyle.plain),
        (text: ' …', style: AnsiStyle.plain),
      ]);
      expect(shown(long, whole: true), [
        (text: 'x' * 1500, style: red),
        (text: 'y' * 1000, style: AnsiStyle.plain),
      ]);
      expect(shown('\x1b[31m${'x' * previewLineLength}\x1b[0m'), [
        (text: 'x' * previewLineLength, style: red),
      ]);
    });
  });
}
