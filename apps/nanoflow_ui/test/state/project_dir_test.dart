import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/state/project_dir.dart';
import 'package:path/path.dart' as p;

void main() {
  late String dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nanoflow_project_dir').path;
  });

  tearDown(() => Directory(dir).deleteSync(recursive: true));

  void put(String path) => File(p.join(dir, path)).createSync(recursive: true);

  test('is the one over the nearest lib/ or bin/ with a pubspec.yaml', () {
    put('app/pubspec.yaml');
    expect(
      projectDirOf(
        p.join(dir, 'app/lib/src/generate/generateIdeas.graph.json'),
      ),
      p.join(dir, 'app'),
    );
    expect(
      projectDirOf(p.join(dir, 'app/bin/main.graph.json')),
      p.join(dir, 'app'),
    );
    // A source directory named lib has no pubspec.yaml over it.
    expect(
      projectDirOf(p.join(dir, 'app/lib/src/lib/a.graph.json')),
      p.join(dir, 'app'),
    );
  });

  test('is the one over the nearest lib/ or bin/ without a pubspec.yaml, as '
      'next to a built program', () {
    expect(
      projectDirOf(p.join(dir, 'build/lib/src/a.graph.json')),
      p.join(dir, 'build'),
    );
  });

  test('is the directory of the file without lib/ or bin/ over it', () {
    expect(
      projectDirOf(p.join(dir, 'graphs', 'a.graph.json')),
      p.join(dir, 'graphs'),
    );
  });
}
