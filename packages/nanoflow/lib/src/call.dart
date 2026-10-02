import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'build.dart';
import 'dart_types.dart';
import 'exec.dart';
import 'vertex.dart';

/// `--call <node>`: runs one step of the node [name] of [graph] and gives the
/// exit code.
///
/// The input is the first line of stdin: the node's data as one line of
/// JSON, an empty line when the node has no `in`. stdin stays open; its end
/// means "stop", as SIGINT and SIGTERM do. A stop ends every program [exec]
/// runs, with its process group, and gives 1 for the end of stdin, 130 for
/// SIGINT and 143 for SIGTERM.
///
/// When the node's function returns, a worker with `out` prints the result
/// as one line of JSON; a fork prints its outcome: `true` or `false` for an
/// if, the key as a JSON string for a switch; a worker without `out` prints
/// nothing. That gives 0. An input that does not fit the node, or an
/// exception of the function — also one that nothing awaits — goes to
/// stderr, the exception with its stack trace, and gives 1.
///
/// However the step ends, programs [exec] started that still run are
/// stopped, with their process groups, before anything is printed: none
/// outlives the step.
Future<int> callNode(BuiltGraph graph, String name) async {
  final vertex = graph.nodes[name];
  if (vertex == null) {
    stderr.writeln('unknown node "$name"');
    return 1;
  }
  final nodes = graph.graphJson['nodes']! as Map<String, Object?>;
  final node = nodes[name]! as Map<String, Object?>;

  final ended = Completer<_End>();
  void end(_End how) {
    if (!ended.isCompleted) ended.complete(how);
  }

  ProcessSignal.sigint.watch().listen((_) => end(const _Stop(130)));
  ProcessSignal.sigterm.watch().listen((_) => end(const _Stop(143)));
  final line = Completer<Uint8List>();
  final read = BytesBuilder(copy: false);
  stdin.listen(
    (bytes) {
      if (line.isCompleted) return;
      final newline = bytes.indexOf(0x0A);
      read.add(newline < 0 ? bytes : bytes.sublist(0, newline));
      if (newline >= 0) line.complete(read.takeBytes());
    },
    onError: (Object _) => end(const _Stop(1)),
    onDone: () => end(const _Stop(1)),
  );
  runZonedGuarded(
    () => unawaited(_step(vertex, node, line.future).then(end)),
    (error, stack) => end(_Failed(_failure(error, stack))),
  );

  final how = await ended.future;
  await stopRunning();
  switch (how) {
    case _Stop(:final exitCode):
      return exitCode;
    case _Done(:final output):
      if (output != null) stdout.writeln(output);
      return 0;
    case _Failed(:final message):
      stderr.writeln(message);
      return 1;
  }
}

/// Decodes the input [line] for [vertex], calls its function and makes the
/// output; [node] is the node's JSON.
Future<_End> _step(
  Vertex<Object?, Object?> vertex,
  Map<String, Object?> node,
  Future<Uint8List> line,
) async {
  final bytes = await line;
  Object? input;
  if (node.containsKey('in')) {
    try {
      input = decodeAs(inputTypeOf(vertex), jsonDecode(utf8.decode(bytes)));
    } on FormatException catch (e) {
      return _Failed('invalid input: ${e.message}');
    }
  }
  try {
    final result = await callVertex(vertex, input);
    return _Done(switch (vertex) {
      Worker() =>
        node.containsKey('out') ? jsonEncode(encodeValue(result)) : null,
      Fork() => jsonEncode(
        outcomeTypeOf(vertex) == bool ? result : outcomeKey(result),
      ),
    });
  } catch (e, stack) {
    return _Failed(_failure(e, stack));
  }
}

/// What a failure of the function writes to stderr: [error] and [stack].
String _failure(Object error, StackTrace stack) =>
    '$error\n${'$stack'.trimRight()}';

/// How a step ends.
sealed class _End {
  const _End();
}

/// Stopped: by the end of stdin, SIGINT or SIGTERM.
final class _Stop extends _End {
  const _Stop(this.exitCode);

  final int exitCode;
}

/// The function returned; [output] is what to print, if anything.
final class _Done extends _End {
  const _Done(this.output);

  final String? output;
}

/// The input did not fit or the function threw.
final class _Failed extends _End {
  const _Failed(this.message);

  final String message;
}
