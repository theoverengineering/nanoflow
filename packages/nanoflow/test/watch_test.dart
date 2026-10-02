import 'dart:io';

import 'package:nanoflow/src/watch.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('watchedDirectory', () {
    late String temp;

    setUp(() {
      temp = Directory.systemTemp
          .createTempSync('nanoflow_watch_')
          .resolveSymbolicLinksSync();
      addTearDown(() => Directory(temp).deleteSync(recursive: true));
    });

    test('is the root of the package that holds the program', () {
      File(p.join(temp, 'pubspec.yaml')).createSync();
      Directory(p.join(temp, 'bin', 'tool')).createSync(recursive: true);
      expect(watchedDirectory(p.join(temp, 'bin', 'tool', 'graph.dart')), temp);
      expect(watchedDirectory(p.join(temp, 'graph.dart')), temp);
    });

    test('is the nearest package above the program', () {
      File(p.join(temp, 'pubspec.yaml')).createSync();
      final inner = p.join(temp, 'examples', 'review');
      Directory(p.join(inner, 'bin')).createSync(recursive: true);
      File(p.join(inner, 'pubspec.yaml')).createSync();
      expect(watchedDirectory(p.join(inner, 'bin', 'graph.dart')), inner);
    });

    test("is the program's directory when no package holds it", () {
      Directory(p.join(temp, 'graphs')).createSync();
      expect(
        watchedDirectory(p.join(temp, 'graphs', 'graph.dart')),
        p.join(temp, 'graphs'),
      );
    });
  });

  group('isGraphSource', () {
    const root = '/pkg';
    const file = '/pkg/bin/graph.dart';
    bool source(String path, {String program = file}) =>
        isGraphSource(path, root: root, file: program);

    test('is a .dart file anywhere in the package', () {
      expect(source('/pkg/bin/graph.dart'), isTrue);
      expect(source('/pkg/lib/src/nodes.dart'), isTrue);
      expect(source('/pkg/helpers.dart'), isTrue);
      expect(source('/pkg/lib/build/nodes.dart'), isTrue);
    });

    test('is not a file of another kind', () {
      expect(source('/pkg/lib/nodes.dart.swp'), isFalse);
      expect(source('/pkg/pubspec.yaml'), isFalse);
    });

    test('is not in build/ or in a directory whose name starts with .', () {
      expect(source('/pkg/build/graph.dart'), isFalse);
      expect(source('/pkg/.dart_tool/build/generated/graph.dart'), isFalse);
      expect(source('/pkg/lib/.cache/nodes.dart'), isFalse);
    });

    test('is in such a directory when it holds the program', () {
      const hidden = '/pkg/.ci/graph.dart';
      expect(source('/pkg/.ci/graph.dart', program: hidden), isTrue);
      expect(source('/pkg/.ci/nodes/review.dart', program: hidden), isTrue);
      expect(source('/pkg/.dart_tool/graph.dart', program: hidden), isFalse);
      const built = '/pkg/build/graph.dart';
      expect(source('/pkg/build/nodes.dart', program: built), isTrue);
    });
  });
}
