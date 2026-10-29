// The graph file of a package as a whole: the same every time, named by
// its pubspec.yaml, and none while its sources do not compile or it has no
// name.

import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_describe/nanoflow_describe.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('writes the same file every time', () async {
    final first = await describePackage(fixture('graphs'), packageName: 'x');
    final second = await describePackage(fixture('graphs'), packageName: 'x');
    expect(
      jsonEncode(second.graph!.toJson()),
      jsonEncode(first.graph!.toJson()),
    );
  });

  group('a package of its own', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('nanoflow_describe_test');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    Future<void> write(String path, String text) async {
      final file = File(p.joinAll([dir.path, ...path.split('/')]));
      await file.parent.create(recursive: true);
      await file.writeAsString(text);
    }

    test('is named by its pubspec.yaml', () async {
      await write('pubspec.yaml', 'name: tiny_app # the app\n');
      await write('lib/tiny.dart', 'int answer() => 42;\n');
      final result = await describePackage(dir.path);
      expect(result.errors, isEmpty);
      final sources = {
        'lib/tiny.dart': sourceHash(utf8.encode('int answer() => 42;\n')),
      };
      expectFile(result.graph!.toJson(), {
        'format': 3,
        'package': 'tiny_app',
        'fingerprint': fingerprintOf(sources),
        'sources': sources,
        'builds': <String, Object?>{},
        'workflows': <Object?>[],
        'functions': <String, Object?>{},
        'warnings': <Object?>[],
      });
    });

    test('has no graph while it does not compile', () async {
      await write('lib/fine.dart', 'int answer() => 42;\n');
      await write('lib/broken.dart', "int answer() => 'forty-two';\n");
      final result = await describePackage(dir.path, packageName: 'broken');
      expect(result.graph, isNull);
      expect(result.errors, [
        allOf(startsWith('lib/broken.dart:1:17: '), contains("'String'")),
      ]);
    });

    test('has no graph without a name', () async {
      await write('lib/tiny.dart', 'int answer() => 42;\n');
      final result = await describePackage(dir.path);
      expect(result.graph, isNull);
      expect(result.errors, [
        '${p.join(dir.path, 'pubspec.yaml')}: no package name',
      ]);
    });
  });
}
