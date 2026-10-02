import 'dart:io';

import 'package:test/test.dart';

/// The layout and its tests run on the Dart VM: they must not reach Flutter.
void main() {
  final directive = RegExp(
    r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );

  for (final folder in ['lib/layout', 'test/layout', 'tool']) {
    test('$folder imports neither Flutter nor dart:ui', () {
      final files = Directory(folder)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(files, isNotEmpty);
      for (final file in files) {
        for (final match in directive.allMatches(file.readAsStringSync())) {
          final uri = match.group(1)!;
          expect(uri, isNot(startsWith('package:flutter')), reason: file.path);
          expect(uri, isNot('dart:ui'), reason: file.path);
          // Other parts of the app may use Flutter; only the layout is safe.
          if (uri.startsWith('package:nanoflow_ui/')) {
            expect(
              uri,
              startsWith('package:nanoflow_ui/layout/'),
              reason: file.path,
            );
          }
        }
      }
    });
  }

  test('lib/layout reaches outside itself only through the model', () {
    for (final file in Directory('lib/layout').listSync().whereType<File>()) {
      for (final match in directive.allMatches(file.readAsStringSync())) {
        final uri = match.group(1)!;
        final allowed =
            uri.startsWith('dart:') ||
            uri == 'package:nanoflow_model/nanoflow_model.dart' ||
            !uri.contains(':') && !uri.contains('/');
        expect(allowed, isTrue, reason: '${file.path}: $uri');
      }
    }
  });
}
