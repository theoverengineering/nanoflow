import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_reader/nanoflow_reader.dart';
import 'package:nanoflow_store/nanoflow_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/feed.dart';
import 'support/wait.dart';

/// A graph whose session has every kind of event: `collect`, then `verdict`,
/// which splits the run into `publish` and `notify`.
const graph = {
  'start': 'collect',
  'nodes': {
    'collect': {
      'command': 'collect.sh',
      'in': {'type': 'object'},
      'out': {'type': 'object'},
      'then': 'verdict',
    },
    'verdict': {
      'decide': 'verdict.sh',
      'in': {'type': 'object'},
      'then': {
        'accepted': ['publish', 'notify'],
      },
    },
    'publish': {
      'command': 'publish.sh',
      'in': {'type': 'object'},
    },
    'notify': {
      'command': 'notify.sh',
      'in': {'type': 'object'},
    },
  },
};

void main() {
  test('what nanoflow_store writes, nanoflow_reader gives as the same '
      'models: every event, document, step, a step that gets its output, and '
      'a log', () async {
    final dir = Directory.systemTemp.createTempSync('nanoflow_contract_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final runsDir = p.join(dir.path, runsDirName);

    final session = await FsStore(runsDir).createSession(
      graphName: 'review',
      graph: graph,
      startNodes: [(node: 'collect', takesInput: true)],
      input: (value: {'branch': 'main'}),
    );
    final sessionId = session.session.id;
    final [root] = await session.runs();
    final [collect] = await session.steps(root.id);
    final documents = <String, Object?>{
      collect.inputId!: {'branch': 'main'},
    };

    final feed = Feed(
      FsReader(
        runsDir: runsDir,
        graphName: 'review',
        pollInterval: const Duration(milliseconds: 20),
      ),
    );
    final reader = feed.reader;

    final created = <Step>[collect];
    final finished = <Step>[];

    Future<void> append(Event event) => session.appendEvent(event);

    Future<void> start(Step step, String node) => append(
      StepStarted(
        runId: step.runId,
        time: systemClock(),
        stepId: step.id,
        node: node,
      ),
    );

    /// Finishes [step] with [output] the way the engine does: the document,
    /// `step-finished`, then `outputId` in `step.json` — once the reader has
    /// given the step without it.
    Future<void> finish(Step step, Object? output) async {
      final outputId = await session.writeDocument(output);
      documents[outputId] = output;
      final event = StepFinished(
        runId: step.runId,
        time: systemClock(),
        stepId: step.id,
        exitCode: 0,
        outputId: outputId,
      );
      await append(event);
      await waitFor(
        'the reader to give step ${step.id} and its step-finished',
        () =>
            feed.changes.contains(StepAdded(step)) &&
            feed.changes.contains(EventAdded(event)),
      );
      finished.add(await session.setStepOutput(step, outputId));
    }

    await start(collect, 'collect');
    await finish(collect, {'id': '1', 'path': 'lib/main.dart'});
    final change = finished.last.outputId;
    final verdict = await session.createStep(
      runId: root.id,
      node: 'verdict',
      inputId: change,
    );
    created.add(verdict);
    await start(verdict, 'verdict');
    // A fork's output is its outcome.
    await finish(verdict, 'accepted');
    final (publishRun, publish) = await session.createRun(
      parentId: root.id,
      node: 'publish',
      inputId: change,
    );
    final (notifyRun, notify) = await session.createRun(
      parentId: root.id,
      node: 'notify',
      inputId: change,
    );
    created.addAll([publish, notify]);
    await append(RunSplit(runId: root.id, time: systemClock()));

    await start(publish, 'publish');
    final log = session.openLog(publishRun.id, publish.id)
      ..add(utf8.encode('published lib/main.dart\n'));
    await log.close();
    await append(
      StepFinished(
        runId: publishRun.id,
        time: systemClock(),
        stepId: publish.id,
        exitCode: 0,
        outputId: null,
      ),
    );
    await append(RunFinished(runId: publishRun.id, time: systemClock()));

    await start(notify, 'notify');
    await append(
      StepFinished(
        runId: notifyRun.id,
        time: systemClock(),
        stepId: notify.id,
        exitCode: 1,
        outputId: null,
      ),
    );
    await append(
      RunFailed(
        runId: notifyRun.id,
        time: systemClock(),
        stepId: notify.id,
        error: 'exited with code 1',
      ),
    );

    final runs = [root, publishRun, notifyRun];
    final journals = {
      for (final run in runs) run.id: await session.events(run.id),
    };
    expect(
      {
        for (final events in journals.values)
          for (final event in events) event.name,
      },
      {
        'run-started',
        'step-started',
        'step-finished',
        'run-split',
        'run-finished',
        'run-failed',
      },
    );
    final others = [
      SessionAdded(session.session),
      for (final run in runs) RunAdded(run),
      for (final step in created) StepAdded(step),
      for (final step in finished) StepChanged(step),
      for (final id in documents.keys)
        DocumentAdded(sessionId: sessionId, documentId: id),
    ];
    await feed.settle();

    expect(feed.errors, isEmpty);
    expect(
      feed.changes.where((c) => c is! EventAdded),
      unorderedEquals(others),
    );
    expect(
      feed.changes.whereType<EventAdded>(),
      hasLength(journals.values.fold<int>(0, (n, events) => n + events.length)),
    );
    for (final run in runs) {
      expect([
        for (final change in feed.changes)
          if (change case EventAdded(event: KnownEvent(:final runId))
              when runId == run.id)
            change.event,
      ], journals[run.id]);
    }

    expect(await reader.sessionGraph(sessionId), graph);
    for (final MapEntry(key: id, :value) in documents.entries) {
      expect(await reader.documentValue(sessionId, id), value);
      expect(await session.documentValue(id), value);
    }
    expect(
      await reader
          .stepLog(sessionId, publishRun.id, publish.id)
          .first
          .timeout(const Duration(seconds: 10)),
      'published lib/main.dart\n',
    );
  });
}
