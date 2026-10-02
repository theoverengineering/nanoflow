import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_reader/nanoflow_reader.dart';
import 'package:nanoflow_store/nanoflow_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/feed.dart';
import 'support/wait.dart';

/// The graph file the session keeps a snapshot of: a session stores whatever
/// map it is given.
const graph = <String, Object?>{
  'format': 1,
  'workflows': ['lib/review.dart#review'],
};

void main() {
  test('what nanoflow_store writes, nanoflow_reader gives as the same '
      'models: a session with input, a step that finishes with output, one '
      'that fails with a log, and the end of the session', () async {
    final dir = Directory.systemTemp.createTempSync('nanoflow_contract_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final runsDir = runsDirOf(dir.path);

    final session = await FsStore(runsDir).createSession(
      workflow: 'review',
      graph: graph,
      input: (value: {'branch': 'main'}),
      code: 'sha256:7d3e9f0c',
    );
    final sessionId = session.session.id;
    final documents = <String, Object?>{
      session.session.inputId!: {'branch': 'main'},
    };

    final feed = Feed(
      FsReader(
        runsDir: runsDir,
        pollInterval: const Duration(milliseconds: 20),
      ),
    );
    final reader = feed.reader;

    // The library's order (spec §4.6, D3): the step's record, step-started,
    // then the output document, step-finished and step.json with outputId —
    // once the reader has given the step without it.
    final collect = await session.createStep(
      name: 'collect',
      key: 'collect#1@e3b0c44298fc1c14',
      after: null,
      place: 'lib/review.dart:12',
    );
    await session.appendEvent(
      StepStarted(time: systemClock(), stepId: collect.id),
    );
    final collected = {'id': '1', 'path': 'lib/main.dart'};
    final collectedId = await session.writeDocument(collected);
    documents[collectedId] = collected;
    final collectFinished = StepFinished(
      time: systemClock(),
      stepId: collect.id,
      outputId: collectedId,
    );
    await session.appendEvent(collectFinished);
    await waitFor(
      'the reader to give step collect and its step-finished',
      () =>
          feed.changes.contains(StepAdded(collect)) &&
          feed.changes.contains(
            EventAdded(sessionId: sessionId, event: collectFinished),
          ),
    );
    final collectDone = await session.setStepOutput(collect, collectedId);

    final inspect = await session.createStep(
      name: 'inspect',
      key: 'inspect#1@9f2c1a7b3d5e8f04',
      after: collect.key,
      place: 'lib/review.dart:13',
    );
    await session.appendEvent(
      StepStarted(time: systemClock(), stepId: inspect.id),
    );
    final log = session.openLog(inspect.id)
      ..add(utf8.encode('inspecting lib/main.dart\n'));
    await log.close();
    await session.appendEvent(
      StepFailed(
        time: systemClock(),
        stepId: inspect.id,
        error: 'Exception: no reviewer',
        stack: '#0      inspect (lib/review.dart:30:5)\n',
      ),
    );

    final result = 'skipped';
    final resultId = await session.writeDocument(result);
    documents[resultId] = result;
    await session.appendEvent(
      SessionFinished(time: systemClock(), outputId: resultId),
    );

    final journal = await session.events();
    expect(
      [for (final event in journal) event.name],
      [
        'session-started',
        'step-started',
        'step-finished',
        'step-started',
        'step-failed',
        'session-finished',
      ],
    );
    await feed.settle();

    expect(feed.errors, isEmpty);
    expect(
      feed.changes.where((c) => c is! EventAdded),
      unorderedEquals([
        SessionAdded(session.session),
        StepAdded(collect),
        StepAdded(inspect),
        StepChanged(collectDone),
        for (final id in documents.keys)
          DocumentAdded(sessionId: sessionId, documentId: id),
      ]),
    );
    expect(feed.changes.first, SessionAdded(session.session));
    final given = [
      for (final change in feed.changes)
        if (change is EventAdded) change,
    ];
    expect(given, [
      for (final event in journal)
        EventAdded(sessionId: sessionId, event: event),
    ]);
    expect(await session.steps(), [collectDone, inspect]);

    final state = replaySession([for (final change in given) change.event]);
    expect(state.status, SessionStatus.finished);
    expect(state.outputId, resultId);
    expect(
      [for (final step in state.steps) (step.stepId, step.status)],
      [(collect.id, StepStatus.finished), (inspect.id, StepStatus.failed)],
    );

    for (final MapEntry(key: id, :value) in documents.entries) {
      expect(await reader.documentValue(sessionId, id), value);
      expect(await session.documentValue(id), value);
    }
    expect(
      await reader
          .stepLog(sessionId, inspect.id)
          .first
          .timeout(const Duration(seconds: 10)),
      'inspecting lib/main.dart\n',
    );
    expect(
      reader.logPath(inspect.id),
      p.join(reader.stepPath(inspect.id)!, 'step.log'),
    );
  });
}
