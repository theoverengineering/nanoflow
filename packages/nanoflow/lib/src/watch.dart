import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// `--graph --watch`: prints [description], the program's description of
/// the graph — `null` when the graph does not build — and then a new one
/// each time the graph changes. Runs until the process is killed.
///
/// A change is a change of a `.dart` file under the directory of [file],
/// the program's source file. Once changes settle for 200 ms, the source is
/// run again with `--graph`, with the packages of this program; its stderr
/// goes to stderr, and its description — the last line of its stdout, a
/// JSON object — is printed when it succeeds and differs from the last one
/// printed. Other lines of its stdout go to stderr. While it fails — it does
/// not compile, or the graph does not build — nothing is printed.
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

  Timer? settling;
  // Watching starts before the first description is printed: a change made
  // as soon as it is read is not missed.
  Directory(p.dirname(file)).watch(recursive: true).where(_isDart).listen((_) {
    settling?.cancel();
    settling = Timer(const Duration(milliseconds: 200), rerun);
  });
  if (description != null) stdout.writeln(description);
  return Completer<Never>().future;
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

bool _isDart(FileSystemEvent event) =>
    event.path.endsWith('.dart') ||
    (event is FileSystemMoveEvent &&
        (event.destination?.endsWith('.dart') ?? false));
