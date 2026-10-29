// What the library learns about the project it runs in: the project
// directory (spec §3), the name of a workflow and the place of an effect
// (§4.1, §5.2), the code hash and the snapshot of a graph's files (§4.7;
// file per graph design §4).

import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

/// Whether this is a compiled program, as `dart compile exe` builds it.
const bool isCompiled = bool.fromEnvironment('dart.vm.product');

/// The project directory: where the graph files are, under `lib/` and
/// `bin/`, and `runs/` goes.
///
/// [directory] when given, made absolute. Otherwise, in a [compiled]
/// program, the directory of [executable]; otherwise, when [script] is a
/// snapshot `dart run` made in `<root>/.dart_tool/pub/bin/<package>/`, the
/// directory of `<package>` as `<root>/.dart_tool/package_config.json` gives
/// it; otherwise the nearest ancestor of [script] with a `pubspec.yaml`, or
/// the directory of [script] when none has one. [executable] and [script]
/// are the running program's by default.
///
/// In a pub workspace `.dart_tool` is in the workspace root, whose
/// `pubspec.yaml` is the nearest to such a snapshot, not the package's.
String findProjectDir({
  String? directory,
  bool compiled = isCompiled,
  String? executable,
  Uri? script,
}) {
  if (directory != null) return p.normalize(p.absolute(directory));
  if (compiled) {
    return p.dirname(executable ?? Platform.resolvedExecutable);
  }
  final start = p.dirname((script ?? Platform.script).toFilePath());
  if (_snapshotPackageDir(start) case final dir?) return dir;
  for (var dir = start; ; dir = p.dirname(dir)) {
    if (File(p.join(dir, 'pubspec.yaml')).existsSync()) return dir;
    if (p.dirname(dir) == dir) return start;
  }
}

/// The directory of the package whose snapshot `dart run` made in [dir],
/// when [dir] is `<root>/.dart_tool/pub/bin/<package>`: the `rootUri` of
/// `<package>` in `<root>/.dart_tool/package_config.json`, which is relative
/// to that `.dart_tool`; `null` when [dir] is not such a directory or the
/// config does not give the package.
String? _snapshotPackageDir(String dir) {
  final parts = p.split(dir);
  final at = parts.length - 4;
  if (at < 1 ||
      parts[at] != '.dart_tool' ||
      parts[at + 1] != 'pub' ||
      parts[at + 2] != 'bin') {
    return null;
  }
  final dartTool = p.joinAll(parts.take(at + 1));
  try {
    final config = jsonDecode(
      File(p.join(dartTool, 'package_config.json')).readAsStringSync(),
    );
    if (config case {'packages': final List<Object?> packages}) {
      for (final package in packages) {
        if (package
            case {'name': final String name, 'rootUri': final String rootUri}
            when name == parts[at + 3]) {
          final root = Uri.directory(dartTool).resolve(rootUri);
          return p.normalize(root.toFilePath());
        }
      }
    }
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
  return null;
}

/// `Closure: (Flow, String) => Future<String> from Function 'review': static.`
/// — the form of a top-level function and of a static method, in `dart run`
/// and in a compiled program alike.
final _staticFunction = RegExp(r" from Function '([^']+)': static\.$");

/// The name of [function], a top-level function or a static method, as its
/// `toString()` gives it — a static method's without its class; `null` for
/// any other function, whose name cannot be found.
String? staticNameOf(Function function) =>
    _staticFunction.firstMatch('$function')?.group(1);

/// The name of [workflow], a workflow function the library runs inside —
/// its tests run the engine with them —, as its `toString()` gives it: a
/// static method's without its class.
///
/// Throws an [ArgumentError] when [workflow] is not a top-level function or
/// a static method: a closure's or an instance method's name cannot be
/// found.
String workflowNameOf(Function workflow) =>
    staticNameOf(workflow) ??
    (throw ArgumentError.value(
      workflow,
      'workflow',
      'a workflow function is a top-level function or a static method: '
          'the name of anything else cannot be found',
    ));

/// A frame as the VM prints it: `#3      review (<uri>:22:31)`; a compiled
/// program prints no column.
final _frame = RegExp(r'^#\d+\s+.+? \((.+?):(\d+)(?::\d+)?\)$');

/// Where `f.effect` was called: `path:line` of the first frame of [trace] that
/// is in neither `dart:` nor `package:nanoflow/`; `null` when there is none.
///
/// A file of the project's own [package] (`package:<package>/x.dart`) is
/// `lib/x.dart`; a file under [projectDir] is its path relative to it, with
/// `/`; any other file is as the stack prints it.
String? placeOf(
  StackTrace trace, {
  required String projectDir,
  required String? package,
}) {
  for (final line in const LineSplitter().convert('$trace')) {
    final match = _frame.firstMatch(line);
    if (match == null) continue;
    final uri = match.group(1)!;
    if (uri.startsWith('dart:') || uri.startsWith('package:nanoflow/')) {
      continue;
    }
    return '${_relative(uri, projectDir, package)}:${match.group(2)}';
  }
  return null;
}

String _relative(String uri, String projectDir, String? package) {
  if (package != null && uri.startsWith('package:$package/')) {
    return 'lib/${uri.substring('package:$package/'.length)}';
  }
  if (uri.startsWith('file:')) {
    final path = Uri.parse(uri).toFilePath();
    if (p.isWithin(projectDir, path)) {
      return p.split(p.relative(path, from: projectDir)).join('/');
    }
  }
  return uri;
}

/// The hash of the code that runs: in a [compiled] program the hash of the
/// bytes of [executable] (the running program's by default), otherwise the
/// fingerprint of [sources] of the package in [projectDir] as they are now —
/// those of the graph the session runs, by their paths from the package root
/// —, or of all its sources without them; `null` when it cannot be computed.
Future<String?> codeHashOf(
  String projectDir, {
  Iterable<String>? sources,
  bool compiled = isCompiled,
  String? executable,
}) async {
  try {
    if (compiled) {
      return bytesHash(
        await File(executable ?? Platform.resolvedExecutable).readAsBytes(),
      );
    }
    return fingerprintOf(
      await hashSources(
        projectDir,
        sources ?? await packageSourcePaths(projectDir),
      ),
    );
  } on FileSystemException {
    return null;
  }
}

/// The hash of the code this process runs, by project directory and
/// sources, as [runningCodeHashOf] took it.
final _codeHashes = <String, Future<String?>>{};

/// The hash of the code this process runs ([codeHashOf] of [projectDir] and
/// [sources]), taken once per process and sources, on first use: the code
/// does not change while the process runs, though its sources and its
/// binary may. Sessions started after the sources are edited so have the
/// hash the first one has.
Future<String?> runningCodeHashOf(
  String projectDir, {
  Iterable<String>? sources,
}) {
  // A compiled program's hash is its binary's, whatever the directory.
  final key = isCompiled
      ? ''
      : [projectDir, ...?(sources?.toList()?..sort())].join('\n');
  return _codeHashes.putIfAbsent(
    key,
    () => codeHashOf(projectDir, sources: sources),
  );
}

/// Forgets the hashes [runningCodeHashOf] took: for tests, which change the
/// sources of a project in this process.
void forgetCodeHashes() => _codeHashes.clear();

/// The snapshot of the graph [name] (file per graph design §4): its graph
/// file — `<name>.graph.json` under `lib/` or `bin/` of [projectDir], the
/// first by path — and those of its subgraphs, by chain, as they are now,
/// put together as one graph file of format 3 (`assembleGraphFile`), in its
/// JSON form. A subgraph whose file cannot be read is left out. `null` when
/// the graph has no file, or it cannot be read.
Future<Map<String, Object?>?> graphSnapshotOf(
  String projectDir,
  String name,
) async {
  final fileName = graphFileNameOf(name);
  final String? path;
  try {
    path = (await packageGraphFilePaths(projectDir))
        .where((path) => p.url.basename(path) == fileName)
        .firstOrNull;
  } on FileSystemException {
    return null;
  }
  if (path == null) return null;
  final files = <String, OneGraphFile>{};
  final pending = [path];
  while (pending.isNotEmpty) {
    final next = pending.removeLast();
    if (files.containsKey(next)) continue;
    final file = await _graphFileAt(projectDir, next);
    if (file == null) continue;
    files[next] = file;
    pending.addAll(file.subgraphs);
  }
  return assembleGraphFile(path, files)?.toJson();
}

/// The graph file of one graph at [path] from [projectDir]; `null` when
/// there is none, or it is not one.
Future<OneGraphFile?> _graphFileAt(String projectDir, String path) async {
  try {
    final json = jsonDecode(
      await File(p.joinAll([projectDir, ...path.split('/')])).readAsString(),
    );
    return json is Map<String, Object?> ? OneGraphFile.fromJson(json) : null;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

/// The paths of the sources [snapshot] was read from — its graph's —, by
/// their paths from the package root; `null` without a snapshot.
Iterable<String>? sourcesOfSnapshot(Map<String, Object?>? snapshot) =>
    switch (snapshot?['sources']) {
      final Map<String, Object?> sources => sources.keys,
      _ => null,
    };

final _pubspecName = RegExp(
  r'^name:\s*([A-Za-z_][A-Za-z0-9_]*)\s*$',
  multiLine: true,
);

/// The package of the project in [projectDir]: the `package` of its [graph]
/// file, or else the `name` in its `pubspec.yaml`; `null` when neither is
/// there.
Future<String?> packageOf(
  String projectDir,
  Map<String, Object?>? graph,
) async {
  if (graph?['package'] case final String package) return package;
  try {
    final pubspec = await File(p.join(projectDir, 'pubspec.yaml'))
        .readAsString();
    return _pubspecName.firstMatch(pubspec)?.group(1);
  } on FileSystemException {
    return null;
  }
}
