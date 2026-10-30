// The describe command (spec §7; file per graph design §3): writes the graph
// file of every graph of a package, keeps them fresh while the sources
// change, tells whether they are fresh, and records a built binary in them
// (§6.3).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import 'describe.dart';

const String _usage = '''
Usage: nanoflow_describe [--package <dir>] [--watch | --check]
                         [--fatal-warnings]
       nanoflow_describe [--package <dir>] stamp <binary>

Writes <graph>.graph.json, the graph file of every graph of the package,
next to the Dart file of the graph; the package root is <dir>, or the
current directory.

  --watch          write them again whenever a source under lib/ or bin/
                   changes, until interrupted
  --check          exit 1 when they differ from what would be written
  --fatal-warnings exit 1 when the graphs have warnings (with or without
                   --check)
  stamp <binary>   record the hash of <binary> in their builds, and copy
                   them next to <binary>''';

/// How long the sources must stay unchanged before `--watch` reads them.
const Duration _settle = Duration(milliseconds: 200);

/// How often `--watch` looks at the sources where the file system cannot
/// tell it about changes below a directory.
const Duration _defaultPoll = Duration(milliseconds: 500);

/// Runs `nanoflow_describe` with [args] in the directory [cwd] and returns
/// its exit code: 0, 1 when it failed, 2 when [args] are wrong.
///
/// Prints to [out] and [err], stdout and stderr by default. `--watch` runs
/// until [stop] completes, or until SIGINT when there is no [stop]; with
/// [poll], it looks at the sources that often instead of being told of
/// changes by the file system. [describe] reads the package in place of
/// [describePackage], for tests.
Future<int> runDescribe(
  List<String> args, {
  required String cwd,
  StringSink? out,
  StringSink? err,
  Future<void>? stop,
  Duration? poll,
  Future<DescribeResult> Function(String packageDir) describe = describePackage,
}) async {
  final errors = err ?? stderr;
  String? package;
  String? binary;
  final modes = <String>[];
  var fatalWarnings = false;
  // Whether a value follows the argument at i: a flag is none.
  bool valueAfter(int i) =>
      i + 1 < args.length && !args[i + 1].startsWith('--');
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--package' when package == null && valueAfter(i):
        package = args[++i];
      case '--fatal-warnings' when !fatalWarnings:
        fatalWarnings = true;
      case '--watch' || '--check':
        modes.add(args[i]);
      case 'stamp' when valueAfter(i):
        modes.add('stamp');
        binary = args[++i];
      default:
        errors.writeln(_usage);
        return 2;
    }
  }
  if (modes.length > 1 ||
      (fatalWarnings && modes.any((mode) => mode != '--check'))) {
    errors.writeln(_usage);
    return 2;
  }
  final base = p.normalize(p.absolute(cwd));
  final command = _Command(
    cwd: base,
    root: p.normalize(p.join(base, package ?? '.')),
    out: out ?? stdout,
    err: errors,
    describe: describe,
  );
  if (!await Directory(command.root).exists()) {
    errors.writeln('no directory ${command.shown(command.root)}');
    return 1;
  }
  try {
    return switch (modes.singleOrNull) {
      null => await command.write(fatalWarnings),
      '--check' => await command.check(fatalWarnings),
      '--watch' => await command.watch(stop, poll),
      _ => await command.stamp(binary!),
    };
  } on FileSystemException catch (e) {
    errors.writeln(e);
    return 1;
  }
}

/// The command for the package in [root].
final class _Command {
  _Command({
    required this.cwd,
    required this.root,
    required this.out,
    required this.err,
    required this.describe,
  });

  final String cwd;
  final String root;
  final StringSink out;
  final StringSink err;
  final Future<DescribeResult> Function(String packageDir) describe;

  /// [path], from the package root, as an absolute path.
  String _absolute(String path) => p.joinAll([root, ...path.split('/')]);

  /// [path] as the user would write it from [cwd].
  String shown(String path) => p.relative(path, from: cwd);

  /// Writes the graph files that changed, and removes those of graphs that
  /// are gone; prints the compile errors, and then writes only the files of
  /// graphs whose sources compile and removes nothing.
  Future<int> write(bool fatalWarnings) async {
    final result = await _update();
    result.errors.forEach(err.writeln);
    _printWarnings(result.warnings);
    return result.errors.isEmpty &&
            !(fatalWarnings && result.warnings.isNotEmpty)
        ? 0
        : 1;
  }

  /// Prints [warnings] as `path:line: message`, the path from [cwd].
  void _printWarnings(Iterable<GraphWarning> warnings) {
    for (final warning in warnings) {
      final place = warning.place;
      final where = place == null ? '' : '${_shownPlace(place)}: ';
      err.writeln('$where${warning.message}');
    }
  }

  /// [place], `path:line` from the package root, with the path from [cwd].
  String _shownPlace(String place) {
    final at = place.lastIndexOf(':');
    if (at < 0) return place;
    return '${shown(_absolute(place.substring(0, at)))}${place.substring(at)}';
  }

  /// Whether the graph files are what [write] would write, their `builds`
  /// aside — a stamped file is fresh —, and there is no other.
  Future<int> check(bool fatalWarnings) async {
    final result = await describe(root);
    result.errors.forEach(err.writeln);
    var fresh = result.errors.isEmpty;
    for (final MapEntry(key: path, value: graph) in result.files.entries) {
      final file = _absolute(path);
      final text = await _read(file);
      if (text == null) {
        err.writeln('${shown(file)} is missing: run nanoflow_describe');
        fresh = false;
      } else if (text != _render(graph, _parse(text)?.builds ?? const {})) {
        err.writeln('${shown(file)} is stale: run nanoflow_describe');
        fresh = false;
      }
    }
    if (result.errors.isEmpty) {
      for (final file in await _left(result.files.keys)) {
        err.writeln(
          '${shown(file)} is no graph of the package: run nanoflow_describe',
        );
        fresh = false;
      }
    }
    _printWarnings(result.warnings);
    return fresh && !(fatalWarnings && result.warnings.isNotEmpty) ? 0 : 1;
  }

  /// Records the hash of [binary] in the `builds` of every graph file, and
  /// copies each next to [binary], by its path from the package root;
  /// refuses when a file's fingerprint is not that of its sources.
  Future<int> stamp(String binary) async {
    final graphs = <String, OneGraphFile>{};
    for (final path in await packageGraphFilePaths(root)) {
      final file = _absolute(path);
      final text = await _read(file);
      final graph = text == null ? null : _parse(text);
      if (graph == null) {
        err.writeln(
          '${shown(file)} is not a graph file: '
          'run nanoflow_describe before stamp',
        );
        return 1;
      }
      final sources = await hashSources(root, graph.sources.keys);
      if (fingerprintOf(sources) != graph.fingerprint) {
        err.writeln(
          '${shown(file)} is stale: run nanoflow_describe before stamp',
        );
        return 1;
      }
      graphs[path] = graph;
    }
    if (graphs.isEmpty) {
      err.writeln('no graph files: run nanoflow_describe before stamp');
      return 1;
    }
    final binaryPath = p.normalize(p.join(cwd, binary));
    final List<int> bytes;
    try {
      bytes = await File(binaryPath).readAsBytes();
    } on FileSystemException catch (e) {
      err.writeln(
        'cannot read ${shown(binaryPath)}: ${e.osError?.message ?? e}',
      );
      return 1;
    }
    final built = p.dirname(binaryPath);
    for (final MapEntry(key: path, value: graph) in graphs.entries) {
      final stamped = _render(graph, {
        ...graph.builds,
        p.basename(binaryPath): bytesHash(bytes),
      });
      for (final file in {
        _absolute(path),
        p.joinAll([built, ...path.split('/')]),
      }) {
        await Directory(p.dirname(file)).create(recursive: true);
        if (await _writeIfChanged(file, stamped)) {
          out.writeln('wrote ${shown(file)}');
        }
      }
    }
    return 0;
  }

  /// Writes the graph files, then again whenever a source changes, until
  /// [stop] completes (SIGINT without [stop]).
  ///
  /// Prints a line for every write and for every describe that failed. A
  /// change of the sources that leaves them as they were last described
  /// describes nothing.
  Future<int> watch(Future<void>? stop, Duration? poll) async {
    final stopped = Completer<void>();
    void end() {
      if (!stopped.isCompleted) stopped.complete();
    }

    StreamSubscription<ProcessSignal>? interrupt;
    if (stop == null) {
      interrupt = ProcessSignal.sigint.watch().listen((_) => end());
    } else {
      unawaited(stop.then((_) => end(), onError: (Object _) => end()));
    }

    String? described; // the fingerprint of the sources last described
    // The (place, message) of the warnings of the last describe that
    // completed.
    var known = <(String?, String)>{};
    Future<void> describeOnce() async {
      try {
        final fingerprint = await _fingerprint();
        if (fingerprint == described) return;
        described = fingerprint;
        final result = await _update();
        if (result.errors.isNotEmpty) {
          err.writeln('describe failed: ${result.errors.first}');
        }
        _printWarnings([
          for (final warning in result.warnings)
            if (!known.contains((warning.place, warning.message))) warning,
        ]);
        known = {
          for (final warning in result.warnings)
            (warning.place, warning.message),
        };
      } catch (e) {
        // Anything — a file that cannot be read, the analyzer or the
        // extractor tripping on some code — ends this describe, not the
        // watch.
        described = null; // read the sources again on the next change
        err.writeln('describe failed: $e');
      }
    }

    // One describe at a time; changes while it runs make one more.
    var running = false;
    var again = false;
    var done = Future<void>.value();
    void describe() {
      if (running) {
        again = true;
        return;
      }
      running = true;
      done = () async {
        try {
          do {
            again = false;
            await describeOnce();
          } while (again && !stopped.isCompleted);
        } finally {
          running = false;
        }
      }();
    }

    var code = 0;
    Timer? settle;
    final changes = _changes(poll).listen(
      (_) {
        settle?.cancel();
        settle = Timer(_settle, describe);
      },
      onError: (Object e) {
        err.writeln('stopped watching: $e');
        code = 1;
        end();
      },
      onDone: () {
        err.writeln('stopped watching: the file system ended the watch');
        code = 1;
        end();
      },
    );
    describe();
    await stopped.future;
    settle?.cancel();
    await changes.cancel();
    await interrupt?.cancel();
    await done;
    return code;
  }

  /// Signals when a source may have changed: on an event below `lib/` or
  /// `bin/`; with [poll], or where a directory cannot be watched with all
  /// below it, when the fingerprint of the sources, looked at every [poll]
  /// ([_defaultPoll]), is another than the last time.
  Stream<void> _changes(Duration? poll) {
    final recursive =
        FileSystemEntity.isWatchSupported &&
        (Platform.isMacOS || Platform.isWindows);
    if (poll != null || !recursive) {
      String? last;
      return Stream<void>.periodic(poll ?? _defaultPoll)
          .asyncMap((_) async {
            try {
              return await _fingerprint();
            } on FileSystemException {
              return null; // the describe it starts tells why
            }
          })
          .where((fingerprint) {
            final changed = fingerprint != last;
            last = fingerprint;
            return changed;
          });
    }
    // The file system tells of real paths.
    final real = Directory(root).resolveSymbolicLinksSync();
    bool inSources(String? path) =>
        path != null &&
        const {'lib', 'bin'}.contains(p.split(p.relative(path, from: real))[0]);
    return Directory(real)
        .watch(recursive: true)
        .where(
          (event) =>
              inSources(event.path) ||
              (event is FileSystemMoveEvent && inSources(event.destination)),
        );
  }

  /// The fingerprint of the sources as they are now.
  Future<String> _fingerprint() async =>
      fingerprintOf(await hashSources(root, await packageSourcePaths(root)));

  /// Describes the package and writes the graph files that changed; once
  /// the package compiles, removes the graph files no graph has and the
  /// graph file of the whole package from before (`nanoflow.graph.json`).
  /// Returns what was described: its compile errors and warnings.
  ///
  /// A file keeps the `builds` it has while its sources are the ones it was
  /// stamped with.
  Future<DescribeResult> _update() async {
    final result = await describe(root);
    for (final MapEntry(key: path, value: graph) in result.files.entries) {
      final file = _absolute(path);
      final old = _parse(await _read(file));
      final builds = old != null && old.fingerprint == graph.fingerprint
          ? old.builds
          : const <String, String>{};
      if (await _writeIfChanged(file, _render(graph, builds))) {
        out.writeln('wrote ${shown(file)}');
      }
    }
    // A graph a compile error kept out of the files keeps its own.
    if (result.errors.isEmpty) {
      for (final file in await _left(result.files.keys)) {
        await File(file).delete();
        out.writeln('removed ${shown(file)}');
      }
    }
    return result;
  }

  /// The graph files of the package that are not at [paths], and the graph
  /// file of the whole package from before: what describe would remove.
  Future<List<String>> _left(Iterable<String> paths) async {
    final kept = paths.toSet();
    return [
      if (await File(p.join(root, graphFileName)).exists())
        p.join(root, graphFileName),
      for (final path in await packageGraphFilePaths(root))
        if (!kept.contains(path)) _absolute(path),
    ];
  }
}

/// The text of [graph] with [builds] as its `builds`, sorted by name:
/// pretty-printed with a two-space indent and a newline at the end.
String _render(OneGraphFile graph, Map<String, String> builds) {
  final json = graph.toJson();
  json['builds'] = {
    for (final name in builds.keys.toList()..sort()) name: builds[name],
  };
  return '${const JsonEncoder.withIndent('  ').convert(json)}\n';
}

/// The graph file of one graph in [text], or `null` when [text] is none or
/// not one.
OneGraphFile? _parse(String? text) {
  if (text == null) return null;
  try {
    final json = jsonDecode(text);
    return json is Map<String, Object?> ? OneGraphFile.fromJson(json) : null;
  } on FormatException {
    return null;
  }
}

/// The text of the file at [path], or `null` when there is none.
Future<String?> _read(String path) async {
  try {
    return utf8.decode(await File(path).readAsBytes(), allowMalformed: true);
  } on PathNotFoundException {
    return null;
  }
}

/// Writes [text] to [path] unless it is there already: under the temporary
/// name `.<name>.tmp-<id>` next to it, renamed into place when it is all
/// written, so that no reader sees half of it. Returns whether it wrote.
Future<bool> _writeIfChanged(String path, String text) async {
  if (await _read(path) == text) return false;
  final temporary = File(
    p.join(p.dirname(path), '.${p.basename(path)}.tmp-${newId()}'),
  );
  try {
    await temporary.writeAsString(text, flush: true);
    await temporary.rename(path);
  } on FileSystemException {
    if (await temporary.exists()) await temporary.delete();
    rethrow;
  }
  return true;
}
