// What the recording tools (record_calls.dart, record_copies.dart,
// record_review.dart) share: a fixture package run with the library and
// described, a session directory read as JSON, the way the library wrote it,
// and JSON written for the UI's fixtures.
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_describe/nanoflow_describe.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

/// Records the sessions the library writes for the workflows of the fixture
/// package test/fixtures/[fixture], which has no pubspec (decision D11):
/// describes the package, runs its workflows with [runAll] in it, and writes
/// its graph file and the sessions to the directory [args] names.
Future<void> recordFixture(
  List<String> args,
  String fixture,
  Future<void> Function(String directory) runAll,
) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/record_$fixture.dart <out directory>');
    exitCode = 2;
    return;
  }
  final out = Directory(args.single)..createSync(recursive: true);
  final package = p.normalize(
    p.join(
      p.dirname(Platform.script.toFilePath()),
      '..',
      'test',
      'fixtures',
      fixture,
    ),
  );
  final runs = Directory(runsDirOf(package));
  if (runs.existsSync()) runs.deleteSync(recursive: true);

  final described = await describePackage(package, packageName: fixture);
  final graph = described.graph;
  if (graph == null) {
    described.errors.forEach(stderr.writeln);
    exitCode = 1;
    return;
  }
  writeJson(p.join(out.path, graphFileName), graph.toJson());

  await runAll(package);
  writeJson(p.join(out.path, 'sessions.json'), [
    for (final dir in byPath(runs.listSync()))
      if (dir is Directory && isSessionDirName(p.basename(dir.path)))
        sessionJson(dir),
  ]);
  runs.deleteSync(recursive: true);
  stdout.writeln('wrote ${out.path}');
}

/// A session directory as JSON: the session, its effects' records, its
/// journal's events and its documents' values.
Map<String, Object?> sessionJson(Directory dir) => {
  'session': _read(p.join(dir.path, sessionFileName)),
  'effects': [
    for (final effect in byPath(
      Directory(p.join(dir.path, effectsDirName)).listSync(),
    ))
      _read(p.join(effect.path, effectFileName)),
  ],
  'events': [
    for (final line in File(p.join(dir.path, eventsFileName)).readAsLinesSync())
      if (line.isNotEmpty) jsonDecode(line),
  ],
  'documents': {
    for (final document in byPath(
      Directory(p.join(dir.path, documentsDirName)).listSync(),
    ))
      p.basenameWithoutExtension(document.path):
          (_read(document.path)! as Map<String, Object?>)['value'],
  },
};

/// Writes [json] to [path], indented by two spaces, with a newline at the
/// end.
void writeJson(String path, Object? json) => File(path)
    .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(json)}\n');

/// [entities] sorted by their paths, in place.
List<FileSystemEntity> byPath(List<FileSystemEntity> entities) =>
    entities..sort((a, b) => a.path.compareTo(b.path));

Object? _read(String path) => jsonDecode(File(path).readAsStringSync());
