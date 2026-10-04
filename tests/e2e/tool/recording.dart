// What the recording tools (record_copies.dart, record_review.dart) share:
// a session directory read as JSON, the way the library wrote it, and JSON
// written for the UI's fixtures.
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

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
