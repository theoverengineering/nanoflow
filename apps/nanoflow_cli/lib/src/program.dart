import 'dart:convert';
import 'dart:io';
import 'dart:io' as io show stderr;
import 'dart:typed_data';

import 'package:nanoflow_model/nanoflow_model.dart';

import 'check/check_graph.dart';

/// A graph program did not do what was asked of it.
final class GraphProgramException implements Exception {
  const GraphProgramException(this.message);

  /// What went wrong, for a human.
  final String message;

  @override
  String toString() => 'GraphProgramException: $message';
}

/// A graph program: the command that `run` and `check` get after `--`.
///
/// It runs in the current directory with the environment of this process.
final class GraphProgram {
  /// [command] is the executable and its arguments, such as
  /// `['dart', 'run', 'graph.dart']`; [stderr] is where the program's stderr
  /// goes while it describes the graph, the stderr of this process by
  /// default.
  GraphProgram(List<String> command, {IOSink? stderr})
    : command = List.unmodifiable(command),
      _stderr = stderr ?? io.stderr {
    if (command.isEmpty) {
      throw ArgumentError.value(command, 'command', 'must not be empty');
    }
  }

  final List<String> command;

  final IOSink _stderr;

  /// Runs `--graph` and gives the description it prints, whose graph passes
  /// [checkGraph].
  ///
  /// Throws a [GraphProgramException] when the program does not start, exits
  /// with a code other than 0, or prints no description, and a
  /// [GraphCheckException] when the graph does not pass.
  Future<GraphDescription> describe() async =>
      checkDescription(await _description());

  /// Runs `--graph` and gives the `file` of the description it prints: the
  /// path of the graph file. The graph is not checked.
  ///
  /// Throws a [GraphProgramException] when the program does not start, exits
  /// with a code other than 0, or prints no description.
  Future<String> graphFile() async => (await _description())['file']! as String;

  /// Runs `--graph` and gives the description it prints, read by
  /// [readDescription].
  Future<Map<String, Object?>> _description() async {
    final process = await _start(['--graph']);
    process.stdin.close().ignore();
    final (:code, :out, err: _) = await _finish(process, stderr: _stderr);
    if (code != 0) {
      throw GraphProgramException('--graph exited with code $code');
    }
    try {
      return readDescription(out);
    } on FormatException catch (e) {
      throw GraphProgramException('--graph output: ${e.message}');
    }
  }

  /// Runs `--input` with [raw], the launch input, on stdin, and gives the
  /// JSON it prints: the checked input.
  ///
  /// Throws a [GraphProgramException] when the program does not start, or
  /// prints something that is not JSON; when it exits with a code other than
  /// 0, the message is its stderr — the reason the input did not pass.
  Future<String> validateInput(String raw) async {
    final process = await _start(['--input']);
    process.stdin.add(utf8.encode(raw));
    // A program that needs no input exits without reading it, which breaks
    // the pipe.
    process.stdin.close().ignore();
    final (:code, :out, :err) = await _finish(process);
    if (code != 0) {
      final reason = utf8.decode(err, allowMalformed: true).trim();
      throw GraphProgramException(
        reason.isEmpty ? '--input exited with code $code' : reason,
      );
    }
    try {
      final text = utf8.decode(out).trim();
      jsonDecode(text);
      return text;
    } on FormatException {
      throw const GraphProgramException('--input output: not JSON');
    }
  }

  /// Starts `--call <node>`: one step of [node]. Its stdin, stdout and
  /// stderr are the caller's to handle.
  ///
  /// Throws a [GraphProgramException] when the program does not start.
  Future<Process> startCall(String node) => _start(['--call', node]);

  Future<Process> _start(List<String> call) async {
    try {
      return await Process.start(command.first, [...command.skip(1), ...call]);
    } on ProcessException catch (e) {
      throw GraphProgramException(
        'failed to start ${command.first}: ${e.message}',
      );
    }
  }
}

/// Waits for [process] to exit and gives its code and what it printed. Its
/// stderr goes to [stderr] as it arrives when that is given, and is
/// collected otherwise.
Future<({int code, Uint8List out, Uint8List err})> _finish(
  Process process, {
  IOSink? stderr,
}) async {
  final out = _collect(process.stdout);
  final err = stderr == null
      ? _collect(process.stderr)
      : process.stderr.listen(stderr.add).asFuture(Uint8List(0));
  final code = await process.exitCode;
  return (code: code, out: await out, err: await err);
}

Future<Uint8List> _collect(Stream<List<int>> bytes) async => (await bytes.fold(
  BytesBuilder(copy: false),
  (all, chunk) => all..add(chunk),
)).takeBytes();
