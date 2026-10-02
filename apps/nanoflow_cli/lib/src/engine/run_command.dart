import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';
import 'package:path/path.dart' as p;

import '../check/check_graph.dart';
import '../program.dart';
import 'engine.dart';

/// `nanoflow run -- <program>`: creates a session of the graph that
/// [program] describes and drives it until every run has ended.
///
/// The launch input is read from [stdin] only when a start node takes input,
/// and is checked by the program's `--input` before the session is created.
/// [stdout] gets the session id and a newline once the session exists, and
/// nothing else; [stderr] gets a line for each event of the session.
///
/// Returns 0 when every run ended and none failed, 1 when one failed, and 2
/// when no session was created: the program gave no graph, the graph did not
/// pass check (its errors go to [stderr], one per line), or there was no
/// input or `--input` rejected it.
Future<int> runRun(
  List<String> program, {
  required Stream<List<int>> stdin,
  required IOSink stdout,
  required IOSink stderr,
}) async {
  final graphProgram = GraphProgram(program, stderr: stderr);
  final GraphDescription description;
  try {
    description = await graphProgram.describe();
  } on GraphProgramException catch (e) {
    stderr.writeln('cannot read the graph: ${e.message}');
    return 2;
  } on GraphCheckException catch (e) {
    e.errors.forEach(stderr.writeln);
    return 2;
  }
  final graph = description.graph;
  final startNodes = [
    for (final node in graph.start.names)
      (node: node, takesInput: graph[node]!.input != null),
  ];
  ({Object? value})? input;
  if (startNodes.any((start) => start.takesInput)) {
    final bytes = await stdin.fold(
      BytesBuilder(copy: false),
      (all, chunk) => all..add(chunk),
    );
    final raw = utf8.decode(bytes.takeBytes(), allowMalformed: true);
    if (raw.trim().isEmpty) {
      stderr.writeln('no input on stdin');
      return 2;
    }
    try {
      input = (value: jsonDecode(await graphProgram.validateInput(raw)));
    } on GraphProgramException catch (e) {
      stderr.writeln(e.message);
      return 2;
    }
  }
  // A relative path is relative to the directory the program ran in: this
  // one.
  final file = p.absolute(description.file);
  final session = await FsStore(runsDirOf(file)).createSession(
    graphName: graphNameOf(file),
    graph: graph.json,
    startNodes: startNodes,
    input: input,
  );
  stdout.writeln(session.session.id);
  await stdout.flush();
  return Engine(
    store: session,
    graph: graph,
    program: graphProgram,
    progress: stderr,
  ).drive();
}
