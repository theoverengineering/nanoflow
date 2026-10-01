@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Programs the compiler must reject, excluded from the package's analysis.
///
/// A line that ends with `// error: <code>` must have an analyzer error with
/// that code; the comment line above the statement says what is wrong. No
/// other line may have a diagnostic.
final Directory fixtures = Directory(
  p.join('test', 'fixtures', 'compile_errors'),
);

final RegExp marker = RegExp(r'// error: (\w+)$');

/// One diagnostic of `dart analyze --format=machine`.
typedef Diagnostic = ({
  String severity,
  String code,
  String file,
  int line,
  String message,
});

Diagnostic parse(String line) {
  // SEVERITY|TYPE|CODE|FILE|LINE|COLUMN|LENGTH|MESSAGE
  final fields = line.split('|');
  return (
    severity: fields[0],
    code: fields[2].toLowerCase(),
    file: fields[3],
    line: int.parse(fields[4]),
    message: fields.sublist(7).join('|'),
  );
}

/// The comment closest above line [index] of [lines].
String commentAbove(List<String> lines, int index) {
  for (var i = index - 1; i >= 0; i--) {
    if (lines[i].startsWith('// ')) return lines[i].substring(3);
  }
  return 'line ${index + 1}';
}

/// The expected error code by line number.
typedef Expected = Map<int, ({String code, String what})>;

void main() {
  final files =
      fixtures
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.absolute.path)
          .toList()
        ..sort();
  late List<Diagnostic> diagnostics;

  setUpAll(() async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'analyze',
      '--format=machine',
      ...files,
    ]);
    diagnostics = [
      for (final line in '${result.stdout}\n${result.stderr}'.split('\n'))
        if (line.contains('|')) parse(line),
    ];
  });

  test('there are fixtures', () {
    expect(files, isNotEmpty);
  });

  for (final file in files) {
    final lines = File(file).readAsLinesSync();
    final Expected expected = {
      for (var i = 0; i < lines.length; i++)
        if (marker.firstMatch(lines[i]) case final match?)
          i + 1: (code: match[1]!, what: commentAbove(lines, i)),
    };
    final name = p.basename(file);

    group(name, () {
      for (final MapEntry(key: line, value: (:code, :what))
          in expected.entries) {
        test('rejects: $what (line $line)', () {
          expect(
            diagnostics.where((d) => d.file == file && d.line == line),
            contains(
              isA<Diagnostic>()
                  .having((d) => d.severity, 'severity', 'ERROR')
                  .having((d) => d.code, 'code', code),
            ),
          );
        });
      }

      test('reports nothing on unmarked lines', () {
        expect(
          diagnostics.where(
            (d) => d.file == file && !expected.containsKey(d.line),
          ),
          isEmpty,
        );
      });
    });
  }
}
