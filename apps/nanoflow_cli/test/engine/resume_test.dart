import 'dart:convert';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';
import 'package:test/test.dart';

import '../support/fake_program.dart';
import '../support/helpers.dart';
import '../support/sessions.dart';

/// A session of [graph] as `nanoflow run` creates it, before its first
/// `step-started`: [input] goes to the start nodes that take input. Its
/// steps run through a [FakeProgram] with [nodes], whose `--graph` describes
/// [described], or [graph] when that is not given.
Future<({FakeProgram fake, SessionHandle session})> created(
  Map<String, Object?> graph, {
  Map<String, String> nodes = const {},
  ({Object? value})? input,
  Map<String, Object?>? described,
}) async {
  final fake = FakeProgram(described ?? graph, nodes: nodes);
  final parsed = Graph.fromJson(graph);
  final session = await FsStore(fake.runsDir).createSession(
    graphName: 'graph',
    graph: graph,
    startNodes: [
      for (final node in parsed.start.names)
        (node: node, takesInput: parsed[node]!.input != null),
    ],
    input: input,
  );
  return (fake: fake, session: session);
}

/// The first step of the run [runId], created with the run.
Future<Step> firstStep(SessionHandle session, String runId) async =>
    (await session.steps(runId)).first;

/// Appends the `step-started` of [step], a step of [node].
Future<void> started(SessionHandle session, Step step, String node) =>
    session.appendEvent(
      StepStarted(
        runId: step.runId,
        time: DateTime.now(),
        stepId: step.id,
        node: node,
      ),
    );

/// Appends the `step-finished` of [step].
Future<void> finished(
  SessionHandle session,
  Step step, {
  int exitCode = 0,
  String? outputId,
}) => session.appendEvent(
  StepFinished(
    runId: step.runId,
    time: DateTime.now(),
    stepId: step.id,
    exitCode: exitCode,
    outputId: outputId,
  ),
);

/// Appends the `step-started` and the `step-finished` of [step], a step of
/// [node].
Future<void> ran(
  SessionHandle session,
  Step step,
  String node, {
  int exitCode = 0,
  String? outputId,
}) async {
  await started(session, step, node);
  await finished(session, step, exitCode: exitCode, outputId: outputId);
}

/// Runs `nanoflow run --resume` of [session] with [fake], and checks that
/// stdout is exactly the session id and a newline.
///
/// stdin fails when it is read: `--resume` never reads it.
Future<Outcome> resume(FakeProgram fake, SessionHandle session) async {
  final id = session.session.id;
  final result = await nanoflow([
    'run',
    '--resume',
    id,
    '--',
    fake.path,
  ], stdinStream: Stream.error(StateError('stdin was read')));
  expect(result.out, '$id\n', reason: result.err);
  return result;
}

/// The lines [stderr] must have for the events of the run [runId] from the
/// [from]th on: those the engine wrote.
Future<List<String>> progressFrom(
  SessionHandle session,
  String runId,
  int from,
) async {
  final events = (await session.events(runId)).cast<KnownEvent>();
  final nodes = {
    for (final event in events)
      if (event is StepStarted) event.stepId: event.node,
  };
  return [
    for (final event in events.skip(from)) progressLine(event, nodes, const []),
  ];
}

void main() {
  test('a run that has not started a step starts the step made with it; '
      'stdin is not read', () async {
    final (:fake, :session) = await created(
      {
        'start': 'a',
        'nodes': {
          'a': {'command': 'a', 'in': object, 'then': 'b'},
          'b': {'command': 'b'},
        },
      },
      nodes: {'a': logInput, 'b': 'true'},
      input: (value: {'branch': 'main'}),
    );
    final run = await onlyRun(session);
    final first = await firstStep(session, run.id);
    final result = await resume(fake, session);
    expect(result.code, 0, reason: result.err);
    expect(await journal(session, run.id), [
      'run-started a',
      'step-started a',
      'step-finished 0',
      'step-started b',
      'step-finished 0',
      'run-finished',
    ]);
    final steps = await stepsOf(session, run.id);
    expect(steps, hasLength(2));
    expect(steps.first.step.id, first.id);
    expect(logOf(session, first), '{"branch":"main"}\n');
    // No line of this run was written before: stderr has one for each event.
    await expectProgress(result.err, session);
  });

  test('a step that did not finish runs again: a new step-started for the '
      'same step, and its log goes on', () async {
    final (:fake, :session) = await created(
      {
        'start': 'a',
        'nodes': {
          'a': {'command': 'a', 'then': 'b'},
          'b': {'command': 'b'},
        },
      },
      nodes: {'a': 'echo again >&2', 'b': 'true'},
    );
    final run = await onlyRun(session);
    final first = await firstStep(session, run.id);
    await started(session, first, 'a');
    final log = session.openLog(run.id, first.id)
      ..add(utf8.encode('first time\n'));
    await log.close();
    final result = await resume(fake, session);
    expect(result.code, 0, reason: result.err);
    expect(await journal(session, run.id), [
      'run-started a',
      'step-started a',
      'step-started a',
      'step-finished 0',
      'step-started b',
      'step-finished 0',
      'run-finished',
    ]);
    final events = await session.events(run.id);
    expect(
      [for (final e in events.whereType<StepStarted>().take(2)) e.stepId],
      [first.id, first.id],
    );
    expect(await session.steps(run.id), hasLength(2));
    expect(logOf(session, first), 'first time\nagain\n');
    expect(
      const LineSplitter().convert(result.err),
      await progressFrom(session, run.id, 2),
    );
  });

  test('after a step that finished, the run goes where it leads, and the '
      'step gets the output its step-finished names', () async {
    final (:fake, :session) = await created(
      {
        'start': 'a',
        'nodes': {
          'a': {'command': 'a', 'out': object, 'then': 'b'},
          'b': {'command': 'b', 'in': object},
        },
      },
      // A step that has finished never runs again.
      nodes: {'a': 'exit 9', 'b': logInput},
    );
    final run = await onlyRun(session);
    final first = await firstStep(session, run.id);
    final output = await session.writeDocument({'n': 1});
    // The engine died before it wrote the output into step.json.
    await ran(session, first, 'a', outputId: output);
    final result = await resume(fake, session);
    expect(result.code, 0, reason: result.err);
    expect(await journal(session, run.id), [
      'run-started a',
      'step-started a',
      'step-finished 0',
      'step-started b',
      'step-finished 0',
      'run-finished',
    ]);
    final [a, b] = [for (final s in await stepsOf(session, run.id)) s.step];
    expect(a.outputId, output);
    expect(b.inputId, output);
    expect(logOf(session, b), '{"n":1}\n');
    expect(
      const LineSplitter().convert(result.err),
      await progressFrom(session, run.id, 3),
    );
  });

  group('a step that finished and failed fails its run', () {
    test('a code other than 0', () async {
      final (:fake, :session) = await created(
        {
          'start': 'a',
          'nodes': {
            'a': {'command': 'a', 'then': 'b'},
            'b': {'command': 'b'},
          },
        },
        nodes: {'a': 'exit 9', 'b': 'exit 9'},
      );
      final run = await onlyRun(session);
      await ran(session, await firstStep(session, run.id), 'a', exitCode: 3);
      final result = await resume(fake, session);
      expect(result.code, 1, reason: result.err);
      expect(await journal(session, run.id), [
        'run-started a',
        'step-started a',
        'step-finished 3',
        'run-failed exited with code 3',
      ]);
    });

    test('no output where data was expected: what it printed is not kept, '
        'so the error names both', () async {
      final (:fake, :session) = await created(
        {
          'start': 'a',
          'nodes': {
            'a': {'command': 'a', 'out': object},
          },
        },
        nodes: {'a': 'exit 9'},
      );
      final run = await onlyRun(session);
      await ran(session, await firstStep(session, run.id), 'a');
      final result = await resume(fake, session);
      expect(result.code, 1, reason: result.err);
      expect(await journal(session, run.id), [
        'run-started a',
        'step-started a',
        'step-finished 0',
        'run-failed printed no output or invalid JSON',
      ]);
    });
  });

  test('a fork that finished goes where its outcome leads', () async {
    final (:fake, :session) = await created(
      {
        'start': 'verdict',
        'nodes': {
          'verdict': {
            'decide': 'verdict',
            'then': {'accepted': 'publish', 'rejected': 'notify'},
          },
          'publish': {'command': 'publish'},
          'notify': {'command': 'notify'},
        },
      },
      nodes: {'verdict': 'exit 9', 'publish': 'exit 9', 'notify': 'true'},
    );
    final run = await onlyRun(session);
    final outcome = await session.writeDocument('rejected');
    await ran(
      session,
      await firstStep(session, run.id),
      'verdict',
      outputId: outcome,
    );
    final result = await resume(fake, session);
    expect(result.code, 0, reason: result.err);
    expect(await journal(session, run.id), [
      'run-started verdict',
      'step-started verdict',
      'step-finished 0',
      'step-started notify',
      'step-finished 0',
      'run-finished',
    ]);
  });

  test('the step made for the next node before the engine died is the one '
      'that runs', () async {
    final (:fake, :session) = await created(
      {
        'start': 'a',
        'nodes': {
          'a': {'command': 'a', 'then': 'b'},
          'b': {'command': 'b'},
        },
      },
      nodes: {'a': 'exit 9', 'b': 'true'},
    );
    final run = await onlyRun(session);
    await ran(session, await firstStep(session, run.id), 'a');
    final next = await session.createStep(
      runId: run.id,
      node: 'b',
      inputId: null,
    );
    final result = await resume(fake, session);
    expect(result.code, 0, reason: result.err);
    expect(await journal(session, run.id), [
      'run-started a',
      'step-started a',
      'step-finished 0',
      'step-started b',
      'step-finished 0',
      'run-finished',
    ]);
    final steps = await stepsOf(session, run.id);
    expect(steps, hasLength(2));
    expect(steps.last.step.id, next.id);
  });

  test('a split that was not written: only the missing runs are created, '
      'then all of them run', () async {
    final (:fake, :session) = await created(
      {
        'start': 'a',
        'nodes': {
          'a': {
            'command': 'a',
            'then': ['left', 'right'],
          },
          'left': {'command': 'left'},
          'right': {'command': 'right'},
        },
      },
      nodes: {'a': 'exit 9', 'left': 'true', 'right': 'true'},
    );
    final parent = await onlyRun(session);
    await ran(session, await firstStep(session, parent.id), 'a');
    final (left, _) = await session.createRun(
      parentId: parent.id,
      node: 'left',
      inputId: null,
    );
    final result = await resume(fake, session);
    expect(result.code, 0, reason: result.err);
    expect(await journal(session, parent.id), [
      'run-started a',
      'step-started a',
      'step-finished 0',
      'run-split',
    ]);
    final runs = await session.runs();
    expect(runs, hasLength(3));
    expect(
      [for (final run in runs) run.parentId],
      [null, parent.id, parent.id],
    );
    expect((await runAt(session, 'left')).id, left.id);
    for (final node in ['left', 'right']) {
      expect(await journal(session, (await runAt(session, node)).id), [
        'run-started $node',
        'step-started $node',
        'step-finished 0',
        'run-finished',
      ]);
    }
  });

  test('the runs of a split that was written go on, each from where it '
      'stopped', () async {
    final (:fake, :session) = await created(
      {
        'start': 'a',
        'nodes': {
          'a': {
            'command': 'a',
            'then': ['left', 'right'],
          },
          'left': {'command': 'left'},
          'right': {'command': 'right'},
        },
      },
      nodes: {'a': 'exit 9', 'left': 'true', 'right': 'true'},
    );
    final parent = await onlyRun(session);
    await ran(session, await firstStep(session, parent.id), 'a');
    await session.createRun(parentId: parent.id, node: 'left', inputId: null);
    final (right, rightFirst) = await session.createRun(
      parentId: parent.id,
      node: 'right',
      inputId: null,
    );
    await session.appendEvent(RunSplit(runId: parent.id, time: DateTime.now()));
    await started(session, rightFirst, 'right');
    final result = await resume(fake, session);
    expect(result.code, 0, reason: result.err);
    expect(await journal(session, parent.id), [
      'run-started a',
      'step-started a',
      'step-finished 0',
      'run-split',
    ]);
    expect(await journal(session, (await runAt(session, 'left')).id), [
      'run-started left',
      'step-started left',
      'step-finished 0',
      'run-finished',
    ]);
    expect(await journal(session, right.id), [
      'run-started right',
      'step-started right',
      'step-started right',
      'step-finished 0',
      'run-finished',
    ]);
    expect(await session.runs(), hasLength(3));
  });

  test('the data a run carries goes on from where the run stopped, through '
      'forks and from the split that made it', () async {
    // `a` splits its output into two runs that start at forks without `in`;
    // the workers after the forks get it.
    final (:fake, :session) = await created(
      {
        'start': 'a',
        'nodes': {
          'a': {
            'command': 'a',
            'out': object,
            'then': ['done', 'pending'],
          },
          'done': {'decide': 'done', 'then': 'afterDone'},
          'pending': {'decide': 'pending', 'then': 'afterPending'},
          'afterDone': {'command': 'afterDone', 'in': object},
          'afterPending': {'command': 'afterPending', 'in': object},
        },
      },
      nodes: {
        'a': 'exit 9',
        'done': 'exit 9',
        'pending': 'echo true',
        'afterDone': logInput,
        'afterPending': logInput,
      },
    );
    final parent = await onlyRun(session);
    final data = await session.writeDocument({'n': 1});
    await ran(
      session,
      await firstStep(session, parent.id),
      'a',
      outputId: data,
    );
    final (done, doneFirst) = await session.createRun(
      parentId: parent.id,
      node: 'done',
      inputId: null,
    );
    await session.createRun(
      parentId: parent.id,
      node: 'pending',
      inputId: null,
    );
    await session.appendEvent(RunSplit(runId: parent.id, time: DateTime.now()));
    // The fork of `done` has decided; `pending` has not started.
    await ran(
      session,
      doneFirst,
      'done',
      outputId: await session.writeDocument(true),
    );
    final result = await resume(fake, session);
    expect(result.code, 0, reason: result.err);
    for (final (fork, worker) in [
      ('done', 'afterDone'),
      ('pending', 'afterPending'),
    ]) {
      final steps = await stepsOf(session, (await runAt(session, fork)).id);
      expect([for (final s in steps) s.node], [fork, worker]);
      final after = steps.last.step;
      expect(after.inputId, data, reason: worker);
      expect(logOf(session, after), '{"n":1}\n', reason: worker);
    }
    expect((await runAt(session, 'done')).id, done.id);
  });

  test('the graph of the session drives it, not the one the program '
      'describes now, which need not pass check', () async {
    final (:fake, :session) = await created(
      {
        'start': 'a',
        'nodes': {
          'a': {'command': 'a', 'then': 'b'},
          'b': {'command': 'b'},
        },
      },
      described: {
        'start': 'a',
        'nodes': {
          'a': {'command': 'a', 'then': 'c'},
        },
      },
      nodes: {'a': 'exit 9', 'b': 'true', 'c': 'exit 9'},
    );
    final run = await onlyRun(session);
    await ran(session, await firstStep(session, run.id), 'a');
    final result = await resume(fake, session);
    expect(result.code, 0, reason: result.err);
    expect(await journal(session, run.id), [
      'run-started a',
      'step-started a',
      'step-finished 0',
      'step-started b',
      'step-finished 0',
      'run-finished',
    ]);
  });

  group('a session that has ended is not run: its id, its code, and no new '
      'events', () {
    test('every run finished: 0', () async {
      final (:fake, :session) = await created(
        {
          'start': 'a',
          'nodes': {
            'a': {'command': 'a'},
          },
        },
        nodes: {'a': 'exit 9'},
      );
      final run = await onlyRun(session);
      await ran(session, await firstStep(session, run.id), 'a');
      await session.appendEvent(
        RunFinished(runId: run.id, time: DateTime.now()),
      );
      final before = await journal(session, run.id);
      final result = await resume(fake, session);
      expect(result.code, 0);
      expect(result.err, '');
      expect(await journal(session, run.id), before);
    });

    test('a run failed: 1', () async {
      final (:fake, :session) = await created(
        {
          'start': ['a', 'b'],
          'nodes': {
            'a': {'command': 'a'},
            'b': {'command': 'b'},
          },
        },
        nodes: {'a': 'exit 9', 'b': 'exit 9'},
      );
      final a = await runAt(session, 'a');
      final b = await runAt(session, 'b');
      await ran(session, await firstStep(session, a.id), 'a');
      await session.appendEvent(RunFinished(runId: a.id, time: DateTime.now()));
      final failedStep = await firstStep(session, b.id);
      await ran(session, failedStep, 'b', exitCode: 2);
      await session.appendEvent(
        RunFailed(
          runId: b.id,
          time: DateTime.now(),
          stepId: failedStep.id,
          error: 'exited with code 2',
        ),
      );
      final before = [
        await journal(session, a.id),
        await journal(session, b.id),
      ];
      final result = await resume(fake, session);
      expect(result.code, 1);
      expect(result.err, '');
      expect([
        await journal(session, a.id),
        await journal(session, b.id),
      ], before);
    });
  });

  group('nothing to resume: exit 2', () {
    const graph = {
      'start': 'a',
      'nodes': {
        'a': {'command': 'a'},
      },
    };

    test('no session with the id', () async {
      final fake = FakeProgram(graph);
      final id = newId();
      final args = ['run', '--resume', id, '--', fake.path];
      final none = (
        code: 2,
        out: '',
        err: 'no session $id in ${fake.runsDir}\n',
      );
      // No `runs` yet, then `runs` with another session.
      expect(await nanoflow(args), none);
      await FsStore(fake.runsDir).createSession(
        graphName: 'graph',
        graph: graph,
        startNodes: [(node: 'a', takesInput: false)],
      );
      expect(await nanoflow(args), none);
    });

    test('a program that gives no graph', () async {
      final result = await nanoflow([
        'run',
        '--resume',
        newId(),
        '--',
        script('exit 3\n'),
      ]);
      expect(result, (
        code: 2,
        out: '',
        err: 'cannot read the graph: --graph exited with code 3\n',
      ));
    });
  });
}
