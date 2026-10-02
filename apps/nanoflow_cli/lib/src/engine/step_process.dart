import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';

import '../program.dart';

/// Whether the stdout of a step of [node] is data: a fork's outcome, or the
/// output of a worker with `out`. A worker without `out` prints to its log.
bool printsData(Node node) => switch (node) {
  WorkerNode(:final output) => output != null,
  ForkNode() => true,
};

/// How a step's `--call` ended: its exit code, and what it printed on stdout
/// when that is data — empty when stdout went to the log.
typedef CallEnd = ({int exitCode, Uint8List stdout});

/// One running `--call` of a step.
///
/// The call gets its input line on stdin, which then stays open: its end
/// tells the call to stop. The call's stderr goes to the step's log as it
/// arrives, and so does its stdout unless it is data, which is kept until the
/// call exits.
final class StepCall {
  StepCall._(this._process, this.ended);

  /// Starts `--call <node>` of [program] for a step of [node] and writes
  /// [input], a line without its `\n`, on its stdin.
  ///
  /// Throws a [GraphProgramException] when the program does not start.
  static Future<StepCall> start(
    GraphProgram program,
    Node node, {
    required String input,
    required StepLog log,
  }) async {
    final process = await program.startCall(node.name);
    // A call that exits without reading its stdin breaks the pipe; nothing
    // waits for what was written to it.
    process.stdin.done.ignore();
    process.stdin.add(utf8.encode('$input\n'));
    final data = BytesBuilder(copy: false);
    final read = [
      process.stdout
          .listen(printsData(node) ? data.add : log.add)
          .asFuture<void>(),
      process.stderr.listen(log.add).asFuture<void>(),
    ];
    Future<CallEnd> end() async {
      final exitCode = await process.exitCode;
      process.stdin.close().ignore();
      await Future.wait(read);
      return (exitCode: exitCode, stdout: data.takeBytes());
    }

    return StepCall._(process, end());
  }

  final Process _process;

  /// Completes once the call has exited and all it printed has been read.
  final Future<CallEnd> ended;

  /// Closes the call's stdin: the call stops its command and exits.
  void stop() => _process.stdin.close().ignore();
}
