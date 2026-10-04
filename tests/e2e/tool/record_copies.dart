// Records sessions of copies run by the real library, for the UI's tests of
// copies (apps/nanoflow_ui/test/state/copies_test.dart): runs the workflows
// of test/fixtures/copies with nanoflow, describes the fixture, and writes
// the fixture's graph file and the sessions as the library wrote them.
//
//   cd tests/e2e
//   dart run tool/record_copies.dart ../../apps/nanoflow_ui/test/state/fixtures/copies
//
// Run it again whenever the library changes how it keys effects or what it
// writes for them (decision D1).
import 'dart:io';

import 'package:nanoflow_describe/nanoflow_describe.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

// The fixture is a package without a pubspec (decision D11): its library
// has no package: name to import it by.
// ignore: avoid_relative_lib_imports
import '../test/fixtures/copies/lib/run_all.dart';
import 'recording.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/record_copies.dart <out directory>');
    exitCode = 2;
    return;
  }
  final out = Directory(args.single)..createSync(recursive: true);
  final fixture = p.normalize(
    p.join(
      p.dirname(Platform.script.toFilePath()),
      '..',
      'test',
      'fixtures',
      'copies',
    ),
  );
  final runs = Directory(runsDirOf(fixture));
  if (runs.existsSync()) runs.deleteSync(recursive: true);

  final described = await describePackage(fixture, packageName: 'copies');
  final graph = described.graph;
  if (graph == null) {
    described.errors.forEach(stderr.writeln);
    exitCode = 1;
    return;
  }
  writeJson(p.join(out.path, graphFileName), graph.toJson());

  await runAll(fixture);
  writeJson(p.join(out.path, 'sessions.json'), [
    for (final dir in byPath(runs.listSync()))
      if (dir is Directory && isSessionDirName(p.basename(dir.path)))
        sessionJson(dir),
  ]);
  runs.deleteSync(recursive: true);
  stdout.writeln('wrote ${out.path}');
}
