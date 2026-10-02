import 'dart:async';
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
  StepCall._(this._process, this._reading, this._abandoned, this.ended);

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
    final reading = [
      process.stdout.listen(printsData(node) ? data.add : log.add),
      process.stderr.listen(log.add),
    ];
    // Taken right away: a subscription that is done before `asFuture` is
    // called never completes its future.
    final read = Future.wait([
      for (final subscription in reading) subscription.asFuture<void>(),
    ]);
    final abandoned = Completer<void>();
    Future<CallEnd> end() async {
      final exitCode = await process.exitCode;
      process.stdin.close().ignore();
      await Future.any([read, abandoned.future]);
      return (exitCode: exitCode, stdout: data.takeBytes());
    }

    return StepCall._(process, reading, abandoned, end());
  }

  final Process _process;

  /// The call's stdout and stderr, as they are read.
  final List<StreamSubscription<List<int>>> _reading;

  /// Completed by [kill]: what the call printed is read no further.
  final Completer<void> _abandoned;

  /// Completes once the call has exited and all it printed has been read,
  /// or, after [kill], once it has exited.
  final Future<CallEnd> ended;

  /// Closes the call's stdin: the call stops its command and exits.
  void stop() => _process.stdin.close().ignore();

  /// Kills the call, which has not stopped when asked to, and reads no
  /// further what it printed: the command it started in a process group of
  /// its own may outlive it and keep its stdout and stderr open.
  void kill() {
    _process.kill(ProcessSignal.sigkill);
    for (final subscription in _reading) {
      subscription.cancel().ignore();
    }
    if (!_abandoned.isCompleted) _abandoned.complete();
  }
}
