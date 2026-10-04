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
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_describe/nanoflow_describe.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

// The fixture is a package without a pubspec (decision D11): its library
// has no package: name to import it by.
// ignore: avoid_relative_lib_imports
import '../test/fixtures/copies/lib/run_all.dart';

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
  _write(p.join(out.path, graphFileName), graph.toJson());

  await runAll(fixture);
  _write(p.join(out.path, 'sessions.json'), [
    for (final dir in _sorted(runs.listSync()))
      if (dir is Directory && isSessionDirName(p.basename(dir.path)))
        _session(dir),
  ]);
  runs.deleteSync(recursive: true);
  stdout.writeln('wrote ${out.path}');
}

/// A session directory as JSON: the session, its effects' records, its
/// journal's events and its documents' values.
Map<String, Object?> _session(Directory dir) => {
  'session': _read(p.join(dir.path, sessionFileName)),
  'effects': [
    for (final effect in _sorted(
      Directory(p.join(dir.path, effectsDirName)).listSync(),
    ))
      _read(p.join(effect.path, effectFileName)),
  ],
  'events': [
    for (final line in File(p.join(dir.path, eventsFileName)).readAsLinesSync())
      if (line.isNotEmpty) jsonDecode(line),
  ],
  'documents': {
    for (final document in _sorted(
      Directory(p.join(dir.path, documentsDirName)).listSync(),
    ))
      p.basenameWithoutExtension(document.path):
          (_read(document.path)! as Map<String, Object?>)['value'],
  },
};

List<FileSystemEntity> _sorted(List<FileSystemEntity> entities) =>
    entities..sort((a, b) => a.path.compareTo(b.path));

Object? _read(String path) => jsonDecode(File(path).readAsStringSync());

void _write(String path, Object? json) => File(path)
    .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(json)}\n');
