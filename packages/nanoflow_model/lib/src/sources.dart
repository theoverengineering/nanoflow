// The sources of a package and their hashes: what a graph file's
// `fingerprint` and `sources` are made of. The describe tool writes them and
// the workflow library compares against them, so both must count the same way.
// And the graph files among them, which describe writes next to the sources.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'one_graph_file.dart';

/// Paths, relative to [packageDir] and written with `/`, of the `.dart` files
/// under `lib/` and `bin/`, sorted.
///
/// A directory whose name starts with `.` or is `build` is left out with all
/// that is in it, and so are symbolic links. A missing `lib/` or `bin/` is
/// fine.
Future<List<String>> packageSourcePaths(String packageDir) =>
    _packageFiles(packageDir, (name) => name.endsWith('.dart'));

/// Paths, relative to [packageDir] and written with `/`, of the graph files
/// (`*.graph.json`) under `lib/` and `bin/`, sorted, the directories left out
/// as [packageSourcePaths] leaves them out.
Future<List<String>> packageGraphFilePaths(String packageDir) =>
    _packageFiles(packageDir, (name) => name.endsWith(graphFileSuffix));

/// Paths of the files under `lib/` and `bin/` whose name [wanted] takes.
Future<List<String>> _packageFiles(
  String packageDir,
  bool Function(String name) wanted,
) async {
  final paths = <String>[];
  for (final top in const ['lib', 'bin']) {
    final dir = Directory(p.join(packageDir, top));
    if (await dir.exists()) await _collect(dir, top, wanted, paths);
  }
  return paths..sort();
}

/// Adds the files [wanted] in [dir], which is [path] from the package root,
/// and in the directories below it to [paths].
Future<void> _collect(
  Directory dir,
  String path,
  bool Function(String name) wanted,
  List<String> paths,
) async {
  await for (final entity in dir.list(followLinks: false)) {
    final name = p.basename(entity.path);
    if (entity is Directory) {
      if (!name.startsWith('.') && name != 'build') {
        await _collect(entity, '$path/$name', wanted, paths);
      }
    } else if (entity is File && wanted(name)) {
      paths.add('$path/$name');
    }
  }
}

/// `sha256:` and the hex sha256 of [bytes] once every `\r\n` is `\n`, so a
/// file checked out with other line endings has the same hash.
String sourceHash(List<int> bytes) {
  final lf = BytesBuilder(copy: false);
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] == 0x0D && i + 1 < bytes.length && bytes[i + 1] == 0x0A) {
      continue;
    }
    lf.addByte(bytes[i]);
  }
  return bytesHash(lf.takeBytes());
}

/// `sha256:` and the hex sha256 of [bytes] as they are: a binary.
String bytesHash(List<int> bytes) => 'sha256:${sha256.convert(bytes)}';

/// The [sourceHash] of every file of [paths] (as [packageSourcePaths] gives
/// them) under [packageDir] that exists, by its path. A file that is missing is
/// left out.
Future<Map<String, String>> hashSources(
  String packageDir,
  Iterable<String> paths,
) async {
  final hashes = <String, String>{};
  for (final path in paths) {
    final file = File(p.joinAll([packageDir, ...path.split('/')]));
    try {
      hashes[path] = sourceHash(await file.readAsBytes());
    } on PathNotFoundException {
      continue;
    }
  }
  return hashes;
}

/// `sha256:` and the hex sha256 of the lines `<path> <hash>\n` of
/// [sourceHashes], sorted by path.
String fingerprintOf(Map<String, String> sourceHashes) {
  final paths = sourceHashes.keys.toList()..sort();
  final text = StringBuffer();
  for (final path in paths) {
    text.write('$path ${sourceHashes[path]}\n');
  }
  return bytesHash(utf8.encode(text.toString()));
}
