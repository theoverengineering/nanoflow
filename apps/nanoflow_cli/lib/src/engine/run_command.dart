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
/// [program] describes and drives it until every run has ended; with
/// [resume], `nanoflow run --resume <id> -- <program>`: drives the session
/// [resume] on from where it stopped.
///
/// The launch input is read from [stdin] only when a start node takes input,
/// and is checked by the program's `--input` before the session is created.
/// A session to resume is found next to the program's graph file; it goes
/// by the graph it holds, and [stdin] is not read. While the engine drives a
/// session it holds the session's lock, so that no second engine drives it
/// too. [stdout] gets the session id and a newline before the session is
/// driven, and nothing else; [stderr] gets a line for each event the engine
/// writes, and the `run-started` line of each run it starts at the run's
/// first step. On resume that line may come again: the engine that created
/// the run may have printed it.
///
/// Returns 0 when every run ended and none failed, 1 when one failed, and 2
/// when there was no session to drive: the program gave no graph, the graph
/// did not pass check (its errors go to [stderr], one per line), there was
/// no input or `--input` rejected it, there is no session [resume], or
/// another engine drives it. SIGINT or SIGTERM stops the engine (the
/// session can be resumed): `128 + N` for signal `N`.
Future<int> runRun(
  List<String> program, {
  String? resume,
  required Stream<List<int>> stdin,
  required IOSink stdout,
  required IOSink stderr,
}) async {
  final graphProgram = GraphProgram(program, stderr: stderr);
  final session = resume == null
      ? await _createSession(graphProgram, stdin: stdin, stderr: stderr)
      : await _openSession(graphProgram, resume, stderr: stderr);
  if (session == null) return 2;
  try {
    stdout.writeln(session.session.id);
    await stdout.flush();
    return await _drive(
      Engine(
        store: session,
        graph: Graph.fromJson(session.session.graph),
        program: graphProgram,
        progress: stderr,
      ),
    );
  } finally {
    await session.release();
  }
}

/// Creates a session of the graph [program] describes, with the launch input
/// from [stdin] when a start node takes input; or writes why it cannot to
/// [stderr] and gives `null`.
Future<SessionHandle?> _createSession(
  GraphProgram program, {
  required Stream<List<int>> stdin,
  required IOSink stderr,
}) async {
  final GraphDescription description;
  try {
    description = await program.describe();
  } on GraphProgramException catch (e) {
    stderr.writeln('cannot read the graph: ${e.message}');
    return null;
  } on GraphCheckException catch (e) {
    e.errors.forEach(stderr.writeln);
    return null;
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
      return null;
    }
    try {
      input = (value: jsonDecode(await program.validateInput(raw)));
    } on GraphProgramException catch (e) {
      stderr.writeln(e.message);
      return null;
    }
  }
  // A relative path is relative to the directory the program ran in: this
  // one.
  final file = p.absolute(description.file);
  return FsStore(runsDirOf(file)).createSession(
    graphName: graphNameOf(file),
    graph: graph.json,
    startNodes: startNodes,
    input: input,
  );
}

/// The session [id] in the `runs` next to the graph file of [program]; or
/// `null`, with why on [stderr], when there is none or another engine drives
/// it.
///
/// The graph [program] describes now is not read, only its file: the session
/// goes by the graph it holds.
Future<SessionHandle?> _openSession(
  GraphProgram program,
  String id, {
  required IOSink stderr,
}) async {
  final String file;
  try {
    file = await program.graphFile();
  } on GraphProgramException catch (e) {
    stderr.writeln('cannot read the graph: ${e.message}');
    return null;
  }
  final runsDir = runsDirOf(p.absolute(file));
  final SessionHandle? session;
  try {
    session = await FsStore(runsDir).openSession(id);
  } on SessionBusyException {
    stderr.writeln('session $id is being run by another engine');
    return null;
  }
  if (session == null) stderr.writeln('no session $id in $runsDir');
  return session;
}

/// Drives [engine] until every run of its session has ended, or until the
/// first SIGINT or SIGTERM stops it; gives the engine's code, or `128 + N`
/// after signal `N`.
Future<int> _drive(Engine engine) async {
  ProcessSignal? stoppedBy;
  Future<void>? stopped;
  final watching = [
    for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm])
      signal.watch().listen((signal) {
        if (stoppedBy != null) return;
        stoppedBy = signal;
        stopped = engine.stop();
      }),
  ];
  try {
    final code = await engine.drive();
    await stopped;
    return switch (stoppedBy) {
      final signal? => 128 + signal.signalNumber,
      null => code,
    };
  } finally {
    // A signal watched keeps the process alive.
    await Future.wait([for (final watch in watching) watch.cancel()]);
  }
}
