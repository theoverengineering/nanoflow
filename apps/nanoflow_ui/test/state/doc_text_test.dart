import 'package:nanoflow_ui/state/doc_text.dart';
import 'package:test/test.dart';

DocRun plain(String text) => (text: text, style: DocStyle.plain);
DocRun code(String text) => (text: text, style: DocStyle.code);

/// The runs of the only block of [doc].
List<DocRun> runsOf(String doc) => parseDoc(doc).single.runs;

void main() {
  group('blocks', () {
    test('a paragraph runs its lines on, a blank line starts the next', () {
      expect(parseDoc('Takes the change\nof the branch.\n\nThen ends.'), [
        DocBlock([plain('Takes the change of the branch.')]),
        DocBlock([plain('Then ends.')]),
      ]);
    });

    test('several blank lines are one break, and none at either end', () {
      expect(parseDoc('\n\nOne.\n\n\n\nTwo.\n\n'), [
        DocBlock([plain('One.')]),
        DocBlock([plain('Two.')]),
      ]);
    });

    test('a list item starts a line of its own: • for - * +, its number', () {
      expect(parseDoc('Does:\n- one\n* two\n+ three\n1. four\n2) five'), [
        DocBlock([plain('Does:')]),
        DocBlock([plain('one')], marker: '•'),
        DocBlock([plain('two')], marker: '•'),
        DocBlock([plain('three')], marker: '•'),
        DocBlock([plain('four')], marker: '1.'),
        DocBlock([plain('five')], marker: '2)'),
      ]);
    });

    test('a line under an item goes on with the item', () {
      expect(parseDoc('- one\n  more of it\n- two'), [
        DocBlock([plain('one more of it')], marker: '•'),
        DocBlock([plain('two')], marker: '•'),
      ]);
    });

    test('a fenced block keeps its lines as they are, in code', () {
      expect(
        parseDoc('Like this:\n```dart\nfinal a = 1;\n  b(a);\n```\nDone.'),
        [
          DocBlock([plain('Like this:')]),
          DocBlock([code('final a = 1;\n  b(a);')], isCode: true),
          DocBlock([plain('Done.')]),
        ],
      );
    });

    test('a fence never closed runs to the end', () {
      expect(parseDoc('```\na\nb'), [
        DocBlock([code('a\nb')], isCode: true),
      ]);
    });

    test('nothing but blank lines is no block', () {
      expect(parseDoc(''), isEmpty);
      expect(parseDoc('\n  \n'), isEmpty);
    });
  });

  group('runs', () {
    test('`code` is code', () {
      expect(runsOf('Runs `claude -p` once.'), [
        plain('Runs '),
        code('claude -p'),
        plain(' once.'),
      ]);
    });

    test('a Dart reference [name] is code without its brackets', () {
      expect(runsOf('The change of [branch], see [Report.findings].'), [
        plain('The change of '),
        code('branch'),
        plain(', see '),
        code('Report.findings'),
        plain('.'),
      ]);
    });

    test('a Markdown link is its text', () {
      expect(runsOf('See [the spec](https://example.com/spec) first.'), [
        plain('See the spec first.'),
      ]);
    });

    test('**strong** and *emphasis*', () {
      expect(runsOf('Is **never** run *twice*.'), [
        plain('Is '),
        (text: 'never', style: DocStyle.strong),
        plain(' run '),
        (text: 'twice', style: DocStyle.emphasis),
        plain('.'),
      ]);
    });

    test('a mark without its pair is text as written', () {
      expect(runsOf('a ` b [c d * e ** f'), [plain('a ` b [c d * e ** f')]);
      expect(runsOf('2 * 3 * 4'), [plain('2 * 3 * 4')]);
      expect(runsOf('[] and [ ]'), [plain('[] and [ ]')]);
    });

    test('code keeps the marks inside it', () {
      expect(runsOf('`a*b*c` and `[x]`'), [
        code('a*b*c'),
        plain(' and '),
        code('[x]'),
      ]);
    });
  });
}
