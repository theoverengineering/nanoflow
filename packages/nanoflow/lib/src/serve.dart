import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'build.dart';
import 'call.dart';
import 'dart_types.dart';
import 'graph.dart';
import 'watch.dart';

/// Answers the call of the graph program that [args] name, about [graph],
/// and exits; `main` of a graph program hands its arguments here.
///
/// - `--graph` prints the description of the graph: one line of JSON with
///   the program file and the graph. A graph that does not build gives its
///   errors on stderr, one per line, and exit code 1.
/// - `--graph --watch` prints the description, and then a new one each time
///   a `.dart` file in the program's directory changes the graph. While the
///   program does not compile or the graph does not build, it prints
///   nothing. It runs until it is killed.
/// - `--input` reads the launch input from stdin and prints, as JSON, what
///   [input] makes of it. When [input] throws, the error goes to stderr and
///   the exit code is 1; the same when a start node takes input and there is
///   no [input]. When no start node takes input and there is no [input],
///   stdin is not read and the input is `null`.
/// - `--call <node>` runs one step of the node. Its input is the first line
///   of stdin: the node's data as JSON, an empty line when the node has no
///   `in`. stdin stays open; its end stops the step, as SIGINT and SIGTERM
///   do: the programs `exec` runs end with their process groups, and the
///   exit code is 1, 130 or 143. When the function returns, a worker with
///   `out` prints its result as JSON and a fork its outcome — `true` or
///   `false` for an if, the key as a JSON string for a switch; the exit code
///   is 0. An input that does not fit the node, or an exception of the
///   function — also one that nothing awaits — goes to stderr, and the exit
///   code is 1. However the step ends, the programs `exec` started that
///   still run end with their process groups before `--call` exits.
/// - Any other arguments print the usage on stderr; the exit code is 2.
///
/// stdout carries data only, and only the library writes it, once, at the
/// end. `print` while `serve` runs — in node functions and in [input] — goes
/// to stderr; a `print` that runs before, such as in a top-level initializer
/// that [graph] refers to, still goes to stdout.
Future<Never> serve<I>(
  List<String> args,
  Graph<void Function(I)> graph, {
  I Function(String raw)? input,
}) async {
  final code = await runZoned(
    () => _answer(args, graph, input),
    zoneSpecification: ZoneSpecification(
      print: (_, _, _, line) => stderr.writeln(line),
    ),
  );
  await stdout.flush();
  await stderr.flush();
  exit(code);
}

Future<int> _answer(
  List<String> args,
  Graph<Object?> graph,
  Object? Function(String raw)? input,
) async {
  final file = Platform.script.toFilePath();
  if (args case ['--graph', '--watch']) {
    final built = _build(graph);
    return watchGraph(
      file,
      built == null ? null : jsonEncode(describe(built, file)),
    );
  }
  if (args case ['--graph'] || ['--input'] || ['--call', _]) {
    final built = _build(graph);
    if (built == null) return 1;
    switch (args) {
      case ['--graph']:
        stdout.writeln(jsonEncode(describe(built, file)));
        return 0;
      case ['--input']:
        return _checkInput(built, input);
      case [_, final node]:
        return callNode(built, node);
    }
  }
  stderr.writeln(
    'usage: ${p.basename(file)} --graph [--watch] | --input | --call <node>',
  );
  return 2;
}

/// [graph] built, or `null` when it does not build: then its errors are on
/// stderr, one per line.
BuiltGraph? _build(Graph<Object?> graph) {
  try {
    return buildGraph(graph);
  } on GraphBuildException catch (e) {
    e.errors.forEach(stderr.writeln);
    return null;
  }
}

/// `--input`: prints the launch input that [input] makes of stdin.
Future<int> _checkInput(
  BuiltGraph graph,
  Object? Function(String raw)? input,
) async {
  if (input == null) {
    if (graph.startTakesInput) {
      stderr.writeln(
        'a start node takes input, but serve has no input '
        'function to read it',
      );
      return 1;
    }
    stdout.writeln('null');
    return 0;
  }
  final String json;
  try {
    json = jsonEncode(encodeValue(input(await utf8.decodeStream(stdin))));
  } catch (e) {
    stderr.writeln(e);
    return 1;
  }
  stdout.writeln(json);
  return 0;
}
