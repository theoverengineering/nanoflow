// Records a session of examples/review run by the real library, for the UI's
// tests of the forks a session passed and how they are drawn
// (apps/nanoflow_ui/test/state/passes_test.dart, graph_marks_test.dart and
// test/graph/canvas/canvas_marks_test.dart): copies the example into a
// temporary project, runs its program there as its README does, on the
// branch parseConfig, and writes the example's graph file and the session as
// the library wrote it.
//
//   cd tests/e2e
//   dart run tool/record_review.dart ../../apps/nanoflow_ui/test/state/fixtures/review
//
// Run it again whenever the library changes how it keys effects or what it
// writes for them, or the example changes.
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import 'recording.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/record_review.dart <out directory>');
    exitCode = 2;
    return;
  }
  final out = Directory(args.single)..createSync(recursive: true);
  final root = p.normalize(
    p.join(p.dirname(Platform.script.toFilePath()), '..', '..', '..'),
  );
  final example = p.join(root, 'examples', 'review');
  final project = Directory.systemTemp.createTempSync('nanoflow_review_');
  try {
    _copyExample(example, project.path);
    // The example's program as its README runs it: the code is the
    // repository's, through the workspace's package config; the copy is the
    // project directory, where runs/ goes.
    final run = await Process.run(Platform.resolvedExecutable, [
      'run',
      '--packages=${p.join(root, '.dart_tool', 'package_config.json')}',
      p.join(project.path, 'bin', 'main.dart'),
      'parseConfig',
    ], workingDirectory: project.path);
    if (run.exitCode != 0) {
      stderr.write('${run.stdout}${run.stderr}');
      exitCode = 1;
      return;
    }
    final id = '${run.stdout}'.trim();
    final dir = Directory(runsDirOf(project.path))
        .listSync()
        .whereType<Directory>()
        .singleWhere((dir) => p.basename(dir.path).endsWith(id));

    File(p.join(example, graphFileName))
        .copySync(p.join(out.path, graphFileName));
    writeJson(p.join(out.path, 'sessions.json'), [sessionJson(dir)]);
  } finally {
    project.deleteSync(recursive: true);
  }
  stdout.writeln('wrote ${out.path}');
}

/// Copies what the library reads of the [example] — its sources, its graph
/// file and the name of its package — into [dir]: the session records the
/// graph file as its snapshot and the hash of the sources as its code.
///
/// The copy's pubspec has the name and the SDK alone: outside the
/// workspace, the example's `resolution: workspace` would make `dart run`
/// complain.
void _copyExample(String example, String dir) {
  File(
    p.join(dir, 'pubspec.yaml'),
  ).writeAsStringSync('name: review_example\nenvironment:\n  sdk: ^3.13.0\n');
  File(p.join(example, graphFileName)).copySync(p.join(dir, graphFileName));
  for (final sources in ['lib', 'bin']) {
    for (final file in Directory(
      p.join(example, sources),
    ).listSync(recursive: true).whereType<File>()) {
      final copy = File(p.join(dir, p.relative(file.path, from: example)));
      copy.parent.createSync(recursive: true);
      file.copySync(copy.path);
    }
  }
}
