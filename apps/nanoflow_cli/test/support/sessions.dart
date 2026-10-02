import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fake_program.dart';
import 'helpers.dart';

/// A schema for `in` and `out`: the engine only looks at whether a node
/// has one.
const object = {'type': 'object'};

/// What `nanoflow run` did with a fake program: its exit code, its stderr
/// and the session it made.
typedef Ran = ({int code, String err, SessionHandle session});

/// Runs `nanoflow run` with a [FakeProgram] of [graph] and [nodes] and with
/// [stdin], and checks what every run shows: stdout is exactly the session
/// id and a newline, and stderr has a line for each event of the session.
Future<Ran> runGraph(
  Map<String, Object?> graph, {
  Map<String, String> nodes = const {},
  String stdin = '',
}) async {
  final fake = FakeProgram(graph, nodes: nodes);
  final result = await nanoflow(['run', '--', fake.path], stdin: stdin);
  final session = await onlySession(fake, result);
  await expectProgress(result.err, session);
  return (code: result.code, err: result.err, session: session);
}

/// The one session in the `runs` of [fake], whose id must be all [result]
/// printed on stdout.
Future<SessionHandle> onlySession(FakeProgram fake, Outcome result) async {
  final dirs = Directory(fake.runsDir).listSync();
  expect(dirs, hasLength(1), reason: result.err);
  final name = p.basename(dirs.single.path);
  expect(name, startsWith('graph-'));
  final id = idOfDirName(name)!;
  expect(result.out, '$id\n');
  return (await FsStore(fake.runsDir).openSession(id))!;
}

/// Checks that [stderr] has a line for each event of [session] and nothing
/// else, each run's lines in the order of its journal.
Future<void> expectProgress(String stderr, SessionHandle session) async {
  final lines = const LineSplitter().convert(stderr);
  final runs = await session.runs();
  final all = <String>[];
  for (final run in runs) {
    final events = (await session.events(run.id)).cast<KnownEvent>();
    final children = [
      for (final child in runs)
        if (child.parentId == run.id)
          (await session.events(child.id)).first as RunStarted,
    ];
    final nodes = {
      for (final event in events)
        if (event is StepStarted) event.stepId: event.node,
    };
    final expected = [
      for (final event in events) progressLine(event, nodes, children),
    ];
    expect(lines.where(expected.contains), expected, reason: stderr);
    all.addAll(expected);
  }
  expect(lines.toList()..sort(), all..sort(), reason: stderr);
}

/// The line of [event] on the engine's stderr (D10):
/// `<HH:MM:SS local> <run id first 4> <event> <details>`. [nodes] are the
/// nodes of the run's steps by step id, [children] the `run-started` of the
/// runs its split created.
String progressLine(
  KnownEvent event,
  Map<String, String> nodes,
  List<RunStarted> children,
) {
  String two(int n) => '$n'.padLeft(2, '0');
  String short(String id) => id.substring(0, 4);
  final time = event.time.toLocal();
  final details = switch (event) {
    RunStarted(:final node) || StepStarted(:final node) => ' $node',
    StepFinished(:final stepId, :final exitCode) =>
      ' ${nodes[stepId]} exit $exitCode',
    RunSplit() =>
      ' ${[for (final c in children) '${short(c.runId)} ${c.node}'].join(', ')}',
    RunFinished() => '',
    RunFailed(:final error) => ' $error',
  };
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)} '
      '${short(event.runId)} ${event.name}$details';
}

/// The journal of the run [runId], an event a line: `step-started a`,
/// `step-finished 0`, `run-failed exited with code 3`.
Future<List<String>> journal(SessionHandle session, String runId) async => [
  for (final event in await session.events(runId))
    switch (event) {
      RunStarted(:final node) => 'run-started $node',
      StepStarted(:final node) => 'step-started $node',
      StepFinished(:final exitCode) => 'step-finished $exitCode',
      RunSplit() => 'run-split',
      RunFinished() => 'run-finished',
      RunFailed(:final error) => 'run-failed $error',
      UnknownEvent(:final json) => 'unknown $json',
    },
];

/// The only run of [session].
Future<Run> onlyRun(SessionHandle session) async =>
    (await session.runs()).single;

/// The run of [session] that starts at [node].
Future<Run> runAt(SessionHandle session, String node) async {
  for (final run in await session.runs()) {
    if ((await session.events(run.id)).first case RunStarted(node: final start)
        when start == node) {
      return run;
    }
  }
  throw StateError('no run starts at $node');
}

/// The steps of the run [runId], each with the node of its `step-started`.
Future<List<({Step step, String node})>> stepsOf(
  SessionHandle session,
  String runId,
) async {
  final nodes = {
    for (final event in await session.events(runId))
      if (event is StepStarted) event.stepId: event.node,
  };
  return [
    for (final step in await session.steps(runId))
      (step: step, node: nodes[step.id]!),
  ];
}

/// The directory in [parent] whose name ends with [id].
String dirOf(String parent, String id) =>
    Directory(parent)
        .listSync()
        .singleWhere((entity) => entity.path.endsWith(id))
        .path;

/// The command log of [step].
String logOf(SessionHandle session, Step step) {
  final run = dirOf(session.dir, step.runId);
  final dir = dirOf(p.join(run, 'steps'), step.id);
  return File(p.join(dir, step.log!)).readAsStringSync();
}

/// The `step-finished` of [stepId] in the run [runId].
Future<StepFinished> finishOf(
  SessionHandle session,
  String runId,
  String stepId,
) async =>
    (await session.events(runId))
        .whereType<StepFinished>()
        .singleWhere((e) => e.stepId == stepId);

/// The names of the documents of [session].
List<String> documentsOf(SessionHandle session) => [
  for (final file in Directory(p.join(session.dir, 'documents')).listSync())
    p.basename(file.path),
];

/// A node script that reads its input line and writes it to its log.
const logInput = 'IFS= read -r line\nprintf \'%s\\n\' "\$line" >&2';

/// A node script that fails unless its input line is empty.
const expectNoInput = 'IFS= read -r line\n[ -z "\$line" ] || exit 5';

/// A node script that waits for the file [name] in its directory to appear,
/// and exits with 7 when it has not after 5 s.
String waitForFile(String name) =>
    '''
i=0
while [ ! -e $name ]; do
  i=\$((i + 1))
  [ \$i -gt 100 ] && exit 7
  sleep 0.05
done''';

/// Waits until [condition] holds, checking every 20 ms for up to 5 s.
Future<void> waitFor(bool Function() condition) async {
  for (var i = 0; i < 250; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('timed out');
}
