// The graph screen fed the sessions of docs/design/graph.png, for the
// screen's tests.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart' hide Route;
import 'package:nanoflow_ui/graph/graph_screen.dart';
import 'package:nanoflow_ui/platform/shell.dart';
import 'package:nanoflow_ui/state/graph_model.dart';
import 'package:path/path.dart' as p;

import '../state/support.dart';
import '../support/golden.dart';
import 'canvas/support.dart';

/// The graph file the screen opens: ~/Projects/review/review.yaml.
final reviewFile =
    '${Platform.environment['HOME']}/Projects/review/review.yaml';

/// The sessions column of docs/design/graph.png below a1b2, newest first:
/// f0a5 running with a failed run, 7c3e failed, 4b8d, 9e21 and c7aa
/// finished.
List<Change> olderSessions() => [
  ...splitSession(
    'f0a5',
    DateTime(2026, 9, 21, 13, 27, 40),
    took: 400,
    publish: End.failed,
    notify: End.running,
  ),
  ...splitSession(
    '7c3e',
    DateTime(2026, 9, 21, 12, 40, 2),
    took: 378,
    publish: End.failed,
  ),
  ...discardSession('4b8d', DateTime(2026, 9, 20, 19, 12, 55), took: 184),
  ...splitSession('9e21', DateTime(2026, 9, 20, 11, 40, 17), took: 1300),
  ...discardSession('c7aa', DateTime(2026, 9, 18, 16, 5, 33), took: 112),
];

/// How a run of a test session ends.
enum End { finished, failed, running }

/// Seconds from [t0] to the local time [local].
num _secondsTo(DateTime local) =>
    local.toUtc().difference(t0).inMilliseconds / 1000;

/// The id of the run of the session [id] that [letter] tells apart from
/// its other runs: `r7c3-run`.
String runOf(String id, String letter) => '$letter${id.substring(0, 3)}-run';

/// The session `<id>-s`, started at [start] (local time), whose one run
/// went to `discard` and finished [took] seconds later.
List<Change> discardSession(String id, DateTime start, {required num took}) {
  final s = _secondsTo(start);
  final run =
      Journal(runOf(id, 'r'), node: 'collect', startedAt: s, sessionId: '$id-s')
        ..step('collect', s, end: s + took / 2, output: '$id-change')
        ..step('is-empty', s + took / 2, end: s + took / 2 + 1)
        ..step('discard', s + took / 2 + 1, end: s + took)
        ..finish(s + took);
  return changesOf([run], sessionId: '$id-s');
}

/// The session `<id>-s`, started at [start] (local time), whose root run
/// split at `verdict` into one on `publish` and one on `notify`, which end
/// as [publish] and [notify] say, the last [took] seconds after [start].
List<Change> splitSession(
  String id,
  DateTime start, {
  required num took,
  End publish = End.finished,
  End notify = End.finished,
}) {
  final s = _secondsTo(start);
  final half = s + took / 2;
  final root =
      Journal(runOf(id, 'r'), node: 'collect', startedAt: s, sessionId: '$id-s')
        ..step('collect', s, end: s + 10, output: '$id-change')
        ..step('is-empty', s + 10, end: s + 11)
        ..step('inspect', s + 11, end: half - 1, output: '$id-report')
        ..step('verdict', half - 1, end: half)
        ..split(half);
  Journal child(String node, End end, num endsAt) {
    final run = Journal(
      runOf(id, node[0]),
      parent: root.id,
      node: node,
      startedAt: half,
      sessionId: '$id-s',
    );
    switch (end) {
      case End.finished:
        run
          ..step(node, half, end: endsAt)
          ..finish(endsAt);
      case End.failed:
        run.fail(
          run.step(node, half, end: endsAt, exit: 1),
          endsAt,
          'exited with code 1',
        );
      case End.running:
        run.step(node, half);
    }
    return run;
  }

  return changesOf([
    root,
    child('publish', publish, s + took),
    child('notify', notify, s + took - 5),
  ], sessionId: '$id-s');
}

/// The model of docs/design/graph.png with the sessions below a1b2 too, and
/// the review graph as the current graph; the steps' logs and documents are
/// [files], by default [mockupFiles]. For the screen to own.
GraphModel mockupModel({FakeFiles? files}) {
  final mockup = Mockup();
  return ownedModel(
    current: Graph.fromJson(reviewGraph),
    changes: [
      ...changesOf([mockup.k7f2, mockup.c3d4, mockup.e5f6]),
      ...olderSessions(),
    ],
    outcomes: reviewOutcomes,
    files: files ?? mockupFiles(),
  );
}

/// The log of the step on `notify` in docs/design/graph.png.
const notifyLog = '''
loading report for change c4f1a9
2 findings, 3 subscribers
sending to subscriber 1 of 3 … ok
sending to subscriber 2 of 3 … ok
subscriber 3: 429 too many requests, retrying in 60s
subscriber 3: 429 too many requests, retrying in 120s
''';

/// The directory of session a1b2 of [Mockup], under [reviewFile]'s `runs`.
final mockupSessionDir = p.join(
  runsDirOf(reviewFile),
  sessionDirName('review', t0, 'a1b2-session'),
);

/// The directory of the step [stepId] on [node] of the run [runId] of
/// [Mockup], started at [startedAt] seconds; the run was created at
/// [runAt].
String mockupStepDir(
  String runId,
  num runAt,
  String node,
  String stepId,
  num startedAt,
) => p.join(
  mockupSessionDir,
  runDirName(at(runAt), runId),
  stepsDirName,
  stepDirName(at(startedAt), node, stepId),
);

/// The file of the step on `notify`'s log.
final notifyLogPath = p.join(
  mockupStepDir('e5f6-run', 611.4, 'notify', 'e5f6-notify-0', 612),
  logFileName,
);

/// The file of the document [id] of session a1b2.
String mockupDocumentPath(String id) =>
    p.join(mockupSessionDir, documentsDirName, documentFileName(id));

/// What the documents of [Mockup] hold.
const mockupDocuments = <String, Object?>{
  'request': {'branch': 'feat/step-protocol'},
  'change-1': {'id': 'c4f1a9', 'path': 'src/engine/step.ts'},
  'is-empty-outcome': false,
  'report-1': {
    'change': {'id': 'c4f1a9', 'path': 'src/engine/step.ts'},
    'findings': ['Writes no output.json on exit code 0'],
  },
  'verdict-outcome-1': 'returned',
  'change-2': {'id': 'c4f1b0', 'path': 'src/engine/step.ts'},
  'report-2': {
    'change': {'id': 'c4f1b0', 'path': 'src/engine/step.ts'},
    'findings': [
      'Writes no output.json on exit code 0',
      'Timeout is absent from the protocol',
    ],
  },
  'verdict-outcome-2': 'accepted',
};

/// The directory of the second step on `inspect` of [Mockup].
final inspectStepPath = mockupStepDir(
  'k7f2-run',
  0,
  'inspect',
  'k7f2-inspect-5',
  369,
);

/// The logs and documents of [Mockup] and their files: the step on `notify`
/// has written [notifyLog] so far.
FakeFiles mockupFiles() => FakeFiles(
  logs: const {'e5f6-notify-0': notifyLog},
  documents: mockupDocuments,
  stepPaths: {'k7f2-inspect-5': inspectStepPath},
  logPaths: {'e5f6-notify-0': notifyLogPath},
  documentPaths: {
    for (final id in mockupDocuments.keys) id: mockupDocumentPath(id),
  },
);

/// 12:06:31 local time on 2026-09-24: session t9m4 of
/// docs/design/task-graph.png has been running for 2h 54m 27s.
final taskNow = DateTime(2026, 9, 24, 12, 6, 31).toUtc();

/// The log of the step on `human-review` in docs/design/task-graph.png.
const humanReviewLog = '''
task PLAN-142 · branch feat/step-protocol
reviewer left 2 findings, diff is 214 lines
waiting for a person to answer: accept or changes
answer file: .nanoflow/PLAN-142/answer
waited 1h 00m, still nothing
waited 1h 12m, still nothing
''';

/// The graph file of docs/design/task-graph.png:
/// ~/Projects/agent-tasks/task.yaml.
final taskFile =
    '${Platform.environment['HOME']}/Projects/agent-tasks/task.yaml';

/// The run of docs/design/task-graph.png, started at 09:12:04: round the
/// coder twice and the reviewer once, its last 8 steps at the mockup's
/// times, waiting on `human-review` since 10:53:53; and the outcomes of its
/// forks.
(Journal, Map<String, Object?>) taskRun() {
  num t(int h, int m, int s) => _secondsTo(DateTime(2026, 9, 24, h, m, s));
  final run = Journal(
    't9m4-run',
    node: 'admit',
    startedAt: t(9, 12, 4),
    sessionId: 't9m4-session',
  );
  final outcomes = <String, Object?>{};
  for (final (node, start, end, outcome) in [
    ('admit', t(9, 12, 4), t(9, 12, 5), 'fresh'),
    ('coder', t(9, 12, 5), t(9, 40, 0), null),
    ('coder-status', t(9, 40, 0), t(9, 40, 1), 'go-on'),
    ('coder', t(9, 40, 1), t(10, 5, 0), null),
    ('coder-status', t(10, 5, 0), t(10, 5, 1), 'done'),
    ('checks', t(10, 5, 1), t(10, 9, 0), null),
    ('checks-result', t(10, 9, 0), t(10, 9, 1), 'repair'),
    ('coder', t(10, 9, 1), t(10, 37, 41), null),
    ('coder-status', t(10, 37, 42), t(10, 37, 42) + 0.4, 'done'),
    ('checks', t(10, 37, 43), t(10, 41, 45), null),
    ('checks-result', t(10, 41, 45), t(10, 41, 45) + 0.3, 'pass'),
    ('reviewer', t(10, 41, 46), t(10, 48, 41), null),
    ('review-verdict', t(10, 48, 41), t(10, 48, 41) + 0.5, 'again'),
    ('reviewer', t(10, 48, 42), t(10, 53, 52), null),
    ('review-verdict', t(10, 53, 52), t(10, 53, 52) + 0.4, 'pass'),
  ]) {
    final output = outcome == null ? null : '$node-${run.steps.length}';
    if (output != null) outcomes[output] = outcome;
    run.step(node, start, end: end, output: output);
  }
  run.step('human-review', t(10, 53, 53), input: 'report');
  return (run, outcomes);
}

/// The task graph, its `human-review` taking an input as in the mockup.
Map<String, Object?> taskGraphWithInput() {
  final graph = taskGraph();
  final nodes = graph['nodes']! as Map<String, Object?>;
  (nodes['human-review']! as Map<String, Object?>)['in'] = const {
    'type': 'object',
  };
  return graph;
}

/// The model of docs/design/task-graph.png for the screen to own: session
/// t9m4, and what [more] gives after it. The step on `human-review` has
/// written [humanReviewLog].
GraphModel taskMockupModel({Stream<Change> more = const Stream.empty()}) {
  final (run, outcomes) = taskRun();
  final waiting = run.steps.last.id;
  final start = (run.events.first as KnownEvent).time;
  return ownedModel(
    changes: changesOf(
      [run],
      sessionId: 't9m4-session',
      graph: taskGraphWithInput(),
    ),
    more: more,
    outcomes: outcomes,
    openedAt: taskNow,
    files: FakeFiles(
      logs: {waiting: humanReviewLog},
      logPaths: {
        waiting: p.join(
          runsDirOf(taskFile),
          sessionDirName('task', start, 't9m4-session'),
          runDirName(start, 't9m4-run'),
          stepsDirName,
          stepDirName(
            run.events.whereType<StepStarted>().last.time,
            'human-review',
            waiting,
          ),
          logFileName,
        ),
      },
    ),
  );
}

/// The source of [model], as the tests set it.
FixedSource sourceOf(GraphModel model) => model.source as FixedSource;

/// Pumps a graph screen of [path] (by default [reviewFile]) that owns
/// [model] (by default [mockupModel]) at [now] (by default [Mockup.now]),
/// and lets the feed reach it. Returns the model.
Future<GraphModel> pumpGraphScreen(
  WidgetTester tester, {
  String? path,
  GraphModel? model,
  Shell? shell,
  VoidCallback? onBack,
  DateTime Function()? now,
  Size size = mockupWindow,
}) async {
  final shown = model ?? mockupModel();
  await pumpScreen(
    tester,
    GraphScreen(
      path: path ?? reviewFile,
      shell: shell ?? Shell(environment: const {}),
      onBack: onBack ?? () {},
      openModel: (_, _) => shown,
      now: now ?? () => Mockup.now,
    ),
    size: size,
  );
  await settle(tester);
  return shown;
}
