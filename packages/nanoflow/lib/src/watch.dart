import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// `--graph --watch`: prints [description], the program's description of
/// the graph — `null` when the graph does not build — and then a new one
/// each time the graph changes. Runs until the process is killed.
///
/// A change is a change of a `.dart` file under the directory of [file],
/// the program file. Once changes settle for 200 ms, the program is run again
/// with `--graph`; its stderr goes to stderr, and its description is printed
/// when it succeeds and differs from the last one printed. While it fails —
/// it does not compile, or the graph does not build — nothing is printed.
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
        [...Platform.executableArguments, file, '--graph'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      stderr.write(result.stderr);
      final printed = (result.stdout as String).trim();
      if (result.exitCode == 0 && printed.isNotEmpty && printed != last) {
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

bool _isDart(FileSystemEvent event) =>
    event.path.endsWith('.dart') ||
    (event is FileSystemMoveEvent &&
        (event.destination?.endsWith('.dart') ?? false));
