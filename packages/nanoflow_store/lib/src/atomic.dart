// Writes that a reader never sees half done: a file or a directory is made
// under a temporary name starting with `.` and renamed into place when it is
// complete. Readers ignore every name that starts with `.`.

import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

const JsonEncoder _pretty = JsonEncoder.withIndent('  ');

/// Writes [json] to [path] pretty-printed, with two-space indent and a
/// trailing newline, through `.<name>.tmp-<random>` next to it.
Future<void> writeJsonAtomically(String path, Object? json) async {
  final text = '${_pretty.convert(json)}\n';
  final temporary = File(
    p.join(p.dirname(path), '.${p.basename(path)}.tmp-${newId()}'),
  );
  await temporary.writeAsString(text, flush: true);
  await temporary.rename(path);
}

/// Builds directory [name] in [parent] whole: [build] fills
/// `<parent>/.tmp-<id>`, which is then renamed to `<parent>/<name>`.
///
/// Creates [parent] when there is none. Returns the path of the built
/// directory.
Future<String> buildDirAtomically(
  String parent, {
  required String id,
  required String name,
  required Future<void> Function(String dir) build,
}) async {
  final temporary = await Directory(p.join(parent, '.tmp-$id'))
      .create(recursive: true);
  await build(temporary.path);
  return (await temporary.rename(p.join(parent, name))).path;
}

/// The id of [entity] when it is a directory named `…-<id>` that is built
/// (its name does not start with `.`), otherwise `null`.
String? idOfBuiltDir(FileSystemEntity entity) {
  final name = p.basename(entity.path);
  if (entity is! Directory || name.startsWith('.')) return null;
  return idOfDirName(name);
}
