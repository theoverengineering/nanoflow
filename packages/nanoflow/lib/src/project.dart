// What the library learns about the project it runs in: the project
// directory (spec §3), the name of a workflow and the place of a step
// (§4.1, §5.2), the code hash and the snapshot of the graph file (§4.7).

import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

/// Whether this is a compiled program, as `dart compile exe` builds it.
const bool isCompiled = bool.fromEnvironment('dart.vm.product');

/// The project directory: where the graph file is and `runs/` goes.
///
/// [directory] when given, made absolute. Otherwise, in a [compiled]
/// program, the directory of [executable]; otherwise the nearest ancestor of
/// [script] with a `pubspec.yaml`, or the directory of [script] when none has
/// one. [executable] and [script] are the running program's by default.
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
  for (var dir = start; ; dir = p.dirname(dir)) {
    if (File(p.join(dir, 'pubspec.yaml')).existsSync()) return dir;
    if (p.dirname(dir) == dir) return start;
  }
}

/// `Closure: (Flow, String) => Future<String> from Function 'review': static.`
/// — the form of a top-level function and of a static method, in `dart run`
/// and in a compiled program alike.
final _staticFunction = RegExp(r" from Function '([^']+)': static\.$");

/// The name of [workflow]: the name of the function, as its `toString()`
/// gives it — a static method's without its class.
///
/// Throws an [ArgumentError] when [workflow] is not a top-level function or a
/// static method: a closure's or an instance method's name cannot be found.
String workflowNameOf(Function workflow) =>
    _staticFunction.firstMatch('$workflow')?.group(1) ??
    (throw ArgumentError.value(
      workflow,
      'workflow',
      'a workflow is a top-level function or a static method: '
          'the name of anything else cannot be found',
    ));

/// A frame as the VM prints it: `#3      review (<uri>:22:31)`; a compiled
/// program prints no column.
final _frame = RegExp(r'^#\d+\s+.+? \((.+?):(\d+)(?::\d+)?\)$');

/// Where `f.step` was called: `path:line` of the first frame of [trace] that
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
/// fingerprint of the sources of the package in [projectDir]; `null` when it
/// cannot be computed.
Future<String?> codeHashOf(
  String projectDir, {
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
      await hashSources(projectDir, await packageSourcePaths(projectDir)),
    );
  } on FileSystemException {
    return null;
  }
}

/// The graph file in [projectDir] as it is now, decoded; `null` when there is
/// none or it is not a JSON object.
Future<Map<String, Object?>?> graphSnapshotOf(String projectDir) async {
  try {
    final json = jsonDecode(
      await File(p.join(projectDir, graphFileName)).readAsString(),
    );
    return json is Map<String, Object?> ? json : null;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

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
