import 'dart:io';
import 'dart:typed_data';

import '../program.dart';
import 'check_graph.dart';

/// `nanoflow check`: checks the graph that [program] describes on
/// `--graph`, or, when [program] is `null`, the description on [stdin].
///
/// The problems go to [stdout], one per line; so does the one line
/// `cannot read the graph: <reason>` when there is no description to check.
/// The program's stderr goes to [stderr]. Returns 0 when the graph passes,
/// 1 otherwise.
Future<int> runCheck(
  List<String>? program, {
  required Stream<List<int>> stdin,
  required IOSink stdout,
  required IOSink stderr,
}) async {
  try {
    if (program == null) {
      final bytes = await stdin.fold(
        BytesBuilder(copy: false),
        (all, chunk) => all..add(chunk),
      );
      final Map<String, Object?> description;
      try {
        description = readDescription(bytes.takeBytes());
      } on FormatException catch (e) {
        return _unreadable(stdout, 'stdin: ${e.message}');
      }
      checkDescription(description);
    } else {
      try {
        await GraphProgram(program, stderr: stderr).describe();
      } on GraphProgramException catch (e) {
        return _unreadable(stdout, e.message);
      }
    }
  } on GraphCheckException catch (e) {
    e.errors.forEach(stdout.writeln);
    return 1;
  }
  return 0;
}

int _unreadable(IOSink stdout, String reason) {
  stdout.writeln('cannot read the graph: $reason');
  return 1;
}
