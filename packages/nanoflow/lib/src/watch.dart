import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// `--graph --watch`: prints [description], the program's description of
/// the graph — `null` when the graph does not build — and then a new one
/// each time the graph changes. Runs until the process is killed.
///
/// A change is a change of a `.dart` file in the package of [file], the
/// program's source file: under its [watchedDirectory], as [isGraphSource]
/// tells. So a graph in `lib/` is watched for a program in `bin/` that only
/// holds `main`. Once changes settle for 200 ms, the source is run again
/// with `--graph`, with the packages of this program; its stderr goes to
/// stderr, and its description — the last line of its stdout, a JSON object
/// — is printed when it succeeds and differs from the last one printed.
/// Other lines of its stdout go to stderr. While it fails — it does not
/// compile, or the graph does not build — nothing is printed.
Future<Never> watchGraph(String file, String? description) {
  var last = description;
  var running = false;
  var again = false;

  /// Runs the program again; changes during a run make one more run after.
  Future<void> rerun() async {
    if (running) {
      again = true;
      return;
    }
    running = true;
    do {
      again = false;
      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          ...Platform.executableArguments,
          // The last one counts: one the program got may be relative, or
          // missing when the package config was found next to it.
          if (Isolate.packageConfigSync case final config?)
            '--packages=${config.toFilePath()}',
          file,
          '--graph',
        ],
        stdoutEncoding: _lenientUtf8,
        stderrEncoding: _lenientUtf8,
      );
      stderr.write(result.stderr);
      final lines = const LineSplitter().convert(result.stdout as String);
      final printed = result.exitCode == 0 && lines.isNotEmpty
          ? _description(lines.last)
          : null;
      // A print that ran before serve — in a top-level initializer — went
      // to stdout ahead of the description: it is log.
      final log = printed == null ? lines : lines.take(lines.length - 1);
      log.forEach(stderr.writeln);
      if (printed != null && printed != last) {
        last = printed;
        stdout.writeln(printed);
      }
    } while (again);
    running = false;
  }

  final root = watchedDirectory(file);
  bool changesSource(FileSystemEvent event) => [
    event.path,
    if (event is FileSystemMoveEvent) ?event.destination,
  ].any((path) => isGraphSource(path, root: root, file: file));

  Timer? settling;
  // Watching starts before the first description is printed: a change made
  // as soon as it is read is not missed.
  Directory(root).watch(recursive: true).where(changesSource).listen((_) {
    settling?.cancel();
    settling = Timer(const Duration(milliseconds: 200), rerun);
  });
  if (description != null) stdout.writeln(description);
  return Completer<Never>().future;
}

/// The directory `--graph --watch` watches for the program [file]: the root
/// of the package that holds it — the nearest directory above it with a
/// `pubspec.yaml` — or the directory of [file] when no package does.
String watchedDirectory(String file) {
  final directory = p.dirname(p.absolute(file));
  for (var dir = directory; ; dir = p.dirname(dir)) {
    if (File(p.join(dir, 'pubspec.yaml')).existsSync()) return dir;
    if (p.dirname(dir) == dir) return directory;
  }
}

/// Whether [path], under [root] — the [watchedDirectory] of the program
/// [file] — is a source of the graph: a `.dart` file that is not in `build/`
/// of [root] nor in a directory whose name starts with `.`, such as
/// `.dart_tool/`, unless that directory holds [file].
bool isGraphSource(String path, {required String root, required String file}) {
  if (!path.endsWith('.dart')) return false;
  final relative = p.relative(p.dirname(path), from: root);
  if (relative == '.') return true;
  var dir = root;
  for (final (i, name) in p.split(relative).indexed) {
    dir = p.join(dir, name);
    final skipped = name.startsWith('.') || (i == 0 && name == 'build');
    if (skipped && !p.isWithin(dir, file)) return false;
  }
  return true;
}

/// Output of the program run again is shown even when it is not UTF-8.
const _lenientUtf8 = Utf8Codec(allowMalformed: true);

/// [line] if it is a JSON object, as a description is.
String? _description(String line) {
  try {
    return jsonDecode(line) is Map<String, Object?> ? line : null;
  } on FormatException {
    return null;
  }
}
