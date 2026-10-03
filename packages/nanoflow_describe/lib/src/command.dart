// The describe command (spec §7): writes the graph file of a package, keeps it
// fresh while the sources change, tells whether it is fresh, and records a
// built binary in it (§6.3).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import 'describe.dart';

const String _usage = '''
Usage: nanoflow_describe [--package <dir>] [--watch | --check]
       nanoflow_describe [--package <dir>] stamp <binary>

Writes nanoflow.graph.json, the graph of the package's workflows, in the
package root: <dir>, or the current directory.

  --watch          write it again whenever a source under lib/ or bin/
                   changes, until interrupted
  --check          exit 1 when it differs from what would be written
  stamp <binary>   record the hash of <binary> in its builds, and copy it
                   next to <binary>''';

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
/// changes by the file system.
Future<int> runDescribe(
  List<String> args, {
  required String cwd,
  StringSink? out,
  StringSink? err,
  Future<void>? stop,
  Duration? poll,
}) async {
  final errors = err ?? stderr;
  String? package;
  String? binary;
  final modes = <String>[];
  // Whether a value follows the argument at i: a flag is none.
  bool valueAfter(int i) =>
      i + 1 < args.length && !args[i + 1].startsWith('--');
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--package' when package == null && valueAfter(i):
        package = args[++i];
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
  if (modes.length > 1) {
    errors.writeln(_usage);
    return 2;
  }
  final base = p.normalize(p.absolute(cwd));
  final command = _Command(
    cwd: base,
    root: p.normalize(p.join(base, package ?? '.')),
    out: out ?? stdout,
    err: errors,
  );
  if (!await Directory(command.root).exists()) {
    errors.writeln('no directory ${command.shown(command.root)}');
    return 1;
  }
  try {
    return switch (modes.singleOrNull) {
      null => await command.write(),
      '--check' => await command.check(),
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
  });

  final String cwd;
  final String root;
  final StringSink out;
  final StringSink err;

  String get _file => p.join(root, graphFileName);

  /// [path] as the user would write it from [cwd].
  String shown(String path) => p.relative(path, from: cwd);

  /// Writes the graph file when it changed; the compile errors otherwise.
  Future<int> write() async {
    final errors = await _update();
    errors.forEach(err.writeln);
    return errors.isEmpty ? 0 : 1;
  }

  /// Whether the graph file is what [write] would write, its `builds`
  /// aside: a stamped file is fresh.
  Future<int> check() async {
    final result = await describePackage(root);
    final graph = result.graph;
    if (graph == null) {
      result.errors.forEach(err.writeln);
      return 1;
    }
    final text = await _read(_file);
    if (text == null) {
      err.writeln('${shown(_file)} is missing: run nanoflow_describe');
      return 1;
    }
    if (text != _render(graph, _parse(text)?.builds ?? const {})) {
      err.writeln('${shown(_file)} is stale: run nanoflow_describe');
      return 1;
    }
    return 0;
  }

  /// Records the hash of [binary] in the `builds` of the graph file, and
  /// copies the file next to [binary]; refuses a file whose fingerprint is
  /// not that of the sources.
  Future<int> stamp(String binary) async {
    final text = await _read(_file);
    final graph = text == null ? null : _parse(text);
    if (graph == null) {
      err.writeln(
        '${shown(_file)} is ${text == null ? 'missing' : 'not a graph file'}: '
        'run nanoflow_describe before stamp',
      );
      return 1;
    }
    if (await _fingerprint() != graph.fingerprint) {
      err.writeln(
        '${shown(_file)} is stale: run nanoflow_describe before stamp',
      );
      return 1;
    }
    final path = p.normalize(p.join(cwd, binary));
    final List<int> bytes;
    try {
      bytes = await File(path).readAsBytes();
    } on FileSystemException catch (e) {
      err.writeln('cannot read ${shown(path)}: ${e.osError?.message ?? e}');
      return 1;
    }
    final stamped = _render(graph, {
      ...graph.builds,
      p.basename(path): bytesHash(bytes),
    });
    for (final file in {_file, p.join(p.dirname(path), graphFileName)}) {
      if (await _writeIfChanged(file, stamped)) {
        out.writeln('wrote ${shown(file)}');
      }
    }
    return 0;
  }

  /// Writes the graph file, then again whenever a source changes, until
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
    Future<void> describeOnce() async {
      try {
        final fingerprint = await _fingerprint();
        if (fingerprint == described) return;
        described = fingerprint;
        final errors = await _update();
        if (errors.isNotEmpty) err.writeln('describe failed: ${errors.first}');
      } on FileSystemException catch (e) {
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

  /// Describes the package and writes its graph file when it changed;
  /// returns the compile errors of the sources instead when there are any.
  ///
  /// The file keeps the `builds` it has while the sources are the ones it
  /// was stamped with.
  Future<List<String>> _update() async {
    final result = await describePackage(root);
    final graph = result.graph;
    if (graph == null) return result.errors;
    final old = _parse(await _read(_file));
    final builds = old != null && old.fingerprint == graph.fingerprint
        ? old.builds
        : const <String, String>{};
    if (await _writeIfChanged(_file, _render(graph, builds))) {
      out.writeln('wrote ${shown(_file)}');
    }
    return const [];
  }
}

/// The text of [graph] with [builds] as its `builds`, sorted by name:
/// pretty-printed with a two-space indent and a newline at the end.
String _render(GraphFile graph, Map<String, String> builds) {
  final json = graph.toJson();
  json['builds'] = {
    for (final name in builds.keys.toList()..sort()) name: builds[name],
  };
  return '${const JsonEncoder.withIndent('  ').convert(json)}\n';
}

/// The graph file in [text], or `null` when [text] is none or not one.
GraphFile? _parse(String? text) {
  if (text == null) return null;
  try {
    final json = jsonDecode(text);
    return json is Map<String, Object?> ? GraphFile.fromJson(json) : null;
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
