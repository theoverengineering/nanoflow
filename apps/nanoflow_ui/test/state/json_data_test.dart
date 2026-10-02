import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/state/json_data.dart';

void main() {
  const report = {
    'change': {'id': 'c4f1a9', 'path': 'src/engine/step.ts'},
    'findings': [
      'Writes no output.json on exit code 0',
      'Timeout is absent from the protocol',
    ],
  };

  /// The rows as `<indent>name type text`, `+`/`-` before a closed or open
  /// container.
  List<String> rowsOf(
    Object? value, {
    Set<String> toggled = const {},
    int openDepth = 1,
  }) => [
    for (final row in schemaRows(value, toggled: toggled, openDepth: openDepth))
      '${'  ' * row.depth}'
          '${row.container ? (row.open ? '- ' : '+ ') : ''}'
          '${row.name} ${row.type} ${row.text}',
  ];

  group('the Schema view of data', () {
    test('lists the fields with their JSON type and value', () {
      expect(rowsOf(const {'id': 'c4f1a9', 'path': 'src/engine/step.ts'}), [
        'id string c4f1a9',
        'path string src/engine/step.ts',
      ]);
      expect(rowsOf(const {'n': 3, 'x': 1.5, 'ok': true, 'none': null}), [
        'n number 3',
        'x number 1.5',
        'ok boolean true',
        'none null null',
      ]);
    });

    test('nests objects and arrays, open near the top', () {
      expect(rowsOf(report), [
        '- change object 2 fields',
        '  id string c4f1a9',
        '  path string src/engine/step.ts',
        '- findings array 2 items',
        '  0 string Writes no output.json on exit code 0',
        '  1 string Timeout is absent from the protocol',
      ]);
    });

    test('closes what is deeper', () {
      expect(
        rowsOf(const {
          'a': {
            'b': {'c': 1},
          },
        }),
        ['- a object 1 field', '  + b object 1 field'],
      );
      expect(rowsOf(report, openDepth: 0), [
        '+ change object 2 fields',
        '+ findings array 2 items',
      ]);
    });

    test('opens and closes what was toggled', () {
      expect(rowsOf(report, toggled: {'/change'}), [
        '+ change object 2 fields',
        '- findings array 2 items',
        '  0 string Writes no output.json on exit code 0',
        '  1 string Timeout is absent from the protocol',
      ]);
      final rows = schemaRows(report);
      expect(rows.map((row) => row.path), [
        '/change',
        '/change/id',
        '/change/path',
        '/findings',
        '/findings/0',
        '/findings/1',
      ]);
      expect(rowsOf(report, openDepth: 0, toggled: {'/findings'}), [
        '+ change object 2 fields',
        '- findings array 2 items',
        '  0 string Writes no output.json on exit code 0',
        '  1 string Timeout is absent from the protocol',
      ]);
    });

    test('a value that is not an object is one row; an array, its items', () {
      expect(rowsOf('accepted'), ['value string accepted']);
      expect(rowsOf(false), ['value boolean false']);
      expect(rowsOf(const [1, 2]), ['0 number 1', '1 number 2']);
      expect(rowsOf(const <String, Object?>{}), isEmpty);
    });

    test('shows strings on one line, and the empty one as ""', () {
      expect(rowsOf(const {'s': 'two\nlines', 'e': ''}), [
        r's string two\nlines',
        'e string ""',
      ]);
    });

    test('tells keys that need it apart in the path', () {
      expect(schemaRows(const {'a/b': 1, '~': 2}).map((row) => row.path), [
        '/a~1b',
        '/~0',
      ]);
    });
  });

  group('the JSON view of data', () {
    test('is the data indented by two spaces', () {
      expect(jsonLines(const {'id': 'c4f1a9'}), ['{', '  "id": "c4f1a9"', '}']);
    });

    String parts(String line) => [
      for (final token in jsonTokens(line)) '${token.part.name}:${token.text}',
    ].join(' ');

    test('tells keys, strings, numbers, true, false and null apart', () {
      expect(
        parts('  "id": "c4f1a9",'),
        'space:   key:"id" punctuation:: space:  string:"c4f1a9" '
        'punctuation:,',
      );
      expect(parts('    "n": -1.5e3,'), contains('number:-1.5e3'));
      expect(parts('  true,'), 'space:   literal:true punctuation:,');
      expect(parts('  "x": null'), contains('literal:null'));
      expect(parts('  "change": {'), contains('punctuation:{'));
      expect(parts(']'), 'punctuation:]');
    });

    test('reads strings with quotes and colons in them', () {
      expect(
        parts(r'  "a\"b: c": "d\\",'),
        r'space:   key:"a\"b: c" punctuation:: space:  string:"d\\" '
        'punctuation:,',
      );
    });

    test('takes a line cut in a string as a string to its end', () {
      expect(parts('  "abc …'), 'space:   string:"abc …');
    });
  });

  test('the size of data is that of its JSON in UTF-8', () {
    expect(byteSize(const {'a': 'é'}), 10);
    expect(sizeText(214), '214 B');
    expect(sizeText(12345), '12,345 B');
  });
}
