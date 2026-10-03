import 'package:nanoflow_ui/state/body_path.dart';
import 'package:nanoflow_ui/state/copy_choices.dart';
import 'package:test/test.dart';

void main() {
  const a = [Opened('2')];
  const b = [Opened('5', functionId: 'lib/f.dart#f'), Opened('1')];
  const c = [Opened('7')];

  group('lastChosen: the frame Logs follow', () {
    test('of several frames, the one where a copy was chosen last', () {
      final choices = CopyChoices()
        ..choose('s', a, a.length, 'copy-a')
        ..choose('s', b, b.length, 'copy-b');
      expect(choices.lastChosen('s', [a, b, c]), b);

      choices.choose('s', a, a.length, 'copy-a2');
      expect(choices.lastChosen('s', [a, b, c]), a);
    });

    test('all chosen in it hands Logs back to the frame chosen before, '
        'then to none', () {
      final choices = CopyChoices()
        ..choose('s', a, a.length, 'copy-a')
        ..choose('s', b, b.length, 'copy-b')
        ..choose('s', b, b.length, null);
      expect(choices.lastChosen('s', [a, b]), a);

      choices.choose('s', a, a.length, null);
      expect(choices.lastChosen('s', [a, b]), isNull);
    });

    test('frames not drawn — collapsed, or of another level — are passed '
        'over', () {
      final choices = CopyChoices()
        ..choose('s', a, a.length, 'copy-a')
        ..choose('s', b, b.length, 'copy-b');
      expect(choices.lastChosen('s', [a]), a);
      expect(choices.lastChosen('s', [c]), isNull);
    });

    test('the choices of another session count for nothing', () {
      final choices = CopyChoices()..choose('s', a, a.length, 'copy-a');
      expect(choices.lastChosen('t', [a]), isNull);
    });
  });
}
