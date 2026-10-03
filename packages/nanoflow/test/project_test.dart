import 'dart:convert';
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';
import 'package:nanoflow/src/project.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

Future<String> review(Flow f, String branch) async => branch;

final class Flows {
  static Future<String> release(Flow f, String version) async => version;

  Future<String> instance(Flow f, String x) async => x;
}

/// Writes [text] to [path] under [dir], making the directories it needs.
void put(String dir, String path, String text) {
  File(p.join(dir, path))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);
}

/// A stack trace whose frames are [frames], numbered as the VM prints them.
StackTrace trace(List<String> frames) => StackTrace.fromString(
  [for (final (i, frame) in frames.indexed) '#$i      $frame'].join('\n'),
);

void main() {
  group('the project directory', () {
    test('is the one given, made absolute', () {
      expect(
        findProjectDir(directory: 'some/dir', compiled: true),
        p.normalize(p.absolute('some/dir')),
      );
    });

    test('is the nearest ancestor of the script with a pubspec.yaml', () async {
      final dir = await tempDir();
      put(dir, 'pubspec.yaml', 'name: outer\n');
      put(dir, 'review/pubspec.yaml', 'name: review_example\n');
      put(dir, 'review/bin/tool/main.dart', '');
      expect(
        findProjectDir(
          compiled: false,
          script: Uri.file(p.join(dir, 'review', 'bin', 'tool', 'main.dart')),
        ),
        p.join(dir, 'review'),
      );
    });

    test('is the directory of the script when no ancestor has a '
        'pubspec.yaml', () async {
      final dir = await tempDir();
      put(dir, 'scripts/main.dart', '');
      expect(
        findProjectDir(
          compiled: false,
          script: Uri.file(p.join(dir, 'scripts', 'main.dart')),
        ),
        p.join(dir, 'scripts'),
      );
    });

    test('is the directory of the binary in a compiled program', () async {
      final dir = await tempDir();
      put(dir, 'pubspec.yaml', 'name: review_example\n');
      expect(
        findProjectDir(
          compiled: true,
          executable: p.join(dir, 'build', 'review'),
          script: Uri.file(p.join(dir, 'build', 'review')),
        ),
        p.join(dir, 'build'),
      );
    });
  });

  group('the name of a workflow', () {
    test('is the name of a top-level function', () {
      expect(workflowNameOf(review), 'review');
    });

    test('is the name of a static method, without its class', () {
      expect(workflowNameOf(Flows.release), 'release');
    });

    test('cannot be found for a closure or an instance method', () {
      Future<String> local(Flow f, String x) async => x;
      for (final workflow in <Function>[
        (Flow f, String x) async => x,
        local,
        Flows().instance,
      ]) {
        expect(
          () => workflowNameOf(workflow),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('a top-level function or a static method'),
            ),
          ),
        );
      }
    });
  });

  group('the place of a step', () {
    const projectDir = '/work/review';
    String? place(List<String> frames, {String? package = 'review_example'}) =>
        placeOf(trace(frames), projectDir: projectDir, package: package);

    test('is the first frame outside dart: and package:nanoflow/', () {
      expect(
        place([
          'Flow.step (package:nanoflow/src/flow.dart:40:5)',
          '_rootRun (dart:async/zone.dart:1525:13)',
          'review (file:///work/review/bin/main.dart:22:31)',
          'main (file:///work/review/bin/main.dart:5:3)',
        ]),
        'bin/main.dart:22',
      );
    });

    test('of a file of the package is under lib/', () {
      expect(
        place(['review (package:review_example/review.dart:22:31)']),
        'lib/review.dart:22',
      );
      expect(
        place(['publish (package:review_example/src/release.dart:9:5)']),
        'lib/src/release.dart:9',
      );
    });

    test('of a file in the project directory is relative to it', () {
      expect(
        place([
          'main.<anonymous closure> '
              '(file:///work/review/test/flow_test.dart:12:7)',
        ]),
        'test/flow_test.dart:12',
      );
    });

    test('has no column when the frame has none, as in a compiled '
        'program', () {
      expect(
        place(['main (file:///work/review/bin/main.dart:9)']),
        'bin/main.dart:9',
      );
    });

    test('of any other file is as the stack prints it', () {
      expect(
        place(['run (file:///work/other/lib/run.dart:3:1)']),
        'file:///work/other/lib/run.dart:3',
      );
      expect(
        place(['run (package:other/run.dart:3:1)']),
        'package:other/run.dart:3',
      );
      expect(
        place([
          'review (package:review_example/review.dart:22:31)',
        ], package: null),
        'package:review_example/review.dart:22',
      );
    });

    test('is null when no frame is outside dart: and package:nanoflow/', () {
      expect(
        place([
          'Flow.step (package:nanoflow/src/flow.dart:40:5)',
          '_rootRun (dart:async/zone.dart:1525:13)',
        ]),
        isNull,
      );
      expect(
        placeOf(StackTrace.empty, projectDir: projectDir, package: null),
        isNull,
      );
    });
  });

  group('the code hash', () {
    test('is the fingerprint of the sources of the package in the project '
        'directory', () async {
      final dir = await tempDir();
      put(dir, 'lib/review.dart', 'void review() {}\n');
      put(dir, 'bin/main.dart', 'void main() {}\n');
      put(dir, 'test/review_test.dart', 'void main() {}\n');
      expect(
        await codeHashOf(dir, compiled: false),
        fingerprintOf({
          'bin/main.dart': sourceHash(utf8.encode('void main() {}\n')),
          'lib/review.dart': sourceHash(utf8.encode('void review() {}\n')),
        }),
      );
    });

    test('is the hash of the binary in a compiled program', () async {
      final dir = await tempDir();
      final binary = p.join(dir, 'review');
      File(binary).writeAsBytesSync([0, 1, 2, 255]);
      expect(
        await codeHashOf(dir, compiled: true, executable: binary),
        bytesHash([0, 1, 2, 255]),
      );
    });

    test('is null when it cannot be computed', () async {
      final dir = await tempDir();
      expect(
        await codeHashOf(
          dir,
          compiled: true,
          executable: p.join(dir, 'missing'),
        ),
        isNull,
      );
    });
  });

  group('the snapshot of the graph file', () {
    test('is the file decoded', () async {
      final dir = await tempDir();
      const graph = {
        'format': 1,
        'package': 'review_example',
        'workflows': ['lib/review.dart#review'],
      };
      put(dir, 'nanoflow.graph.json', jsonEncode(graph));
      expect(await graphSnapshotOf(dir), graph);
    });

    test('is null when there is no file', () async {
      expect(await graphSnapshotOf(await tempDir()), isNull);
    });

    test('is null when the file cannot be read as a JSON object', () async {
      for (final text in ['{"format": 1', '[1, 2]']) {
        final dir = await tempDir();
        put(dir, 'nanoflow.graph.json', text);
        expect(await graphSnapshotOf(dir), isNull, reason: text);
      }
      final notUtf8 = await tempDir();
      File(p.join(notUtf8, 'nanoflow.graph.json')).writeAsBytesSync([0xff]);
      expect(await graphSnapshotOf(notUtf8), isNull);
      final directory = await tempDir();
      Directory(p.join(directory, 'nanoflow.graph.json')).createSync();
      expect(await graphSnapshotOf(directory), isNull);
    });
  });

  group('the package of the project', () {
    test('is the package of the graph file', () async {
      final dir = await tempDir();
      put(dir, 'pubspec.yaml', 'name: other\n');
      expect(
        await packageOf(dir, const {'package': 'review_example'}),
        'review_example',
      );
    });

    test('is the name in pubspec.yaml without a graph file', () async {
      final dir = await tempDir();
      put(dir, 'pubspec.yaml', 'description: x\nname: review_example\n');
      expect(await packageOf(dir, null), 'review_example');
    });

    test('is null without either', () async {
      expect(await packageOf(await tempDir(), null), isNull);
    });
  });
}
