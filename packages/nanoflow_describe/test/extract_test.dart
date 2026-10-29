// The graph files of a package as a whole: the same every time, named by its
// pubspec.yaml, none for a graph while its sources do not compile, and none
// without a name.

import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_describe/nanoflow_describe.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('writes the same files every time', () async {
    String text(DescribeResult result) => jsonEncode({
      for (final MapEntry(:key, :value) in result.files.entries)
        key: value.toJson(),
    });
    final first = await describePackage(fixture('graphs'), packageName: 'x');
    final second = await describePackage(fixture('graphs'), packageName: 'x');
    expect(text(second), text(first));
  });

  group('a package of its own', () {
    // Inside the workspace, so that the analyzer finds `package:nanoflow`,
    // in a directory whose name starts with `.`, which `dart analyze` and
    // `dart format` of the workspace pass by.
    late Directory dir;

    setUp(() async {
      dir = await Directory(fixture('')).createTemp('.tmp-');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    Future<void> write(String path, String text) async {
      final file = File(p.joinAll([dir.path, ...path.split('/')]));
      await file.parent.create(recursive: true);
      await file.writeAsString(text);
    }

    /// A graph [name] of one node, importing [imports].
    String graph(String name, {List<String> imports = const []}) =>
        "import 'package:nanoflow/nanoflow.dart';\n"
        "${[for (final i in imports) "import '$i';\n"].join()}"
        "final ${name}Node = node('$name', (String s) async => s);\n"
        "final $name = Graph<String, String>('$name', "
        '[Graph.start(${name}Node)]);\n';

    test('is named by its pubspec.yaml', () async {
      await write('pubspec.yaml', 'name: tiny_app # the app\n');
      await write('lib/tiny.dart', graph('tiny'));
      final result = await describePackage(dir.path);
      expect(result.errors, isEmpty);
      expect(result.files.keys, ['lib/tiny.graph.json']);
      expect(result.files.values.single.package, 'tiny_app');
    });

    test('has no file for a graph whose sources do not compile, and has the '
        'others', () async {
      await write('lib/fine.dart', graph('fine'));
      await write('lib/broken.dart', "int answer() => 'forty-two';\n");
      await write('lib/uses.dart', graph('uses', imports: ['broken.dart']));
      final result = await describePackage(dir.path, packageName: 'broken');
      expect(result.files.keys, ['lib/fine.graph.json']);
      expect(result.graphs.keys, ['lib/fine.dart#fine']);
      expect(result.errors, [
        allOf(startsWith('lib/broken.dart:1:17: '), contains("'String'")),
      ]);
    });

    test('has no graphs without a name', () async {
      await write('lib/tiny.dart', graph('tiny'));
      final result = await describePackage(dir.path);
      expect(result.files, isEmpty);
      expect(result.errors, [
        '${p.join(p.absolute(dir.path), 'pubspec.yaml')}: no package name',
      ]);
    });
  });
}
