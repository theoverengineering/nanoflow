@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_reader/nanoflow_reader.dart';
import 'package:nanoflow_store/nanoflow_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/engine.dart';
import 'support/feed.dart';

void main() {
  setUpAll(compileEngine);

  final example = p.join(repoRoot, 'examples', 'review');

  /// A copy of the example's graph program.
  String copyExample() => copyToTemp([p.join(example, 'graph.dart')]);

  /// The example's `input.json`.
  final exampleInput = File(p.join(example, 'input.json')).readAsStringSync();

  /// Runs `nanoflow run -- dart run graph.dart` in [dir], a copy of the
  /// example, with [input] on stdin; it must end with 0 and print only the
  /// session id. Gives the session.
  Future<SessionHandle> runExample(String dir, String input) async {
    final result = await nanoflow(
      ['run', '--', ...dartRun('graph.dart')],
      dir: dir,
      stdin: input,
    );
    expect(result.code, 0, reason: result.err);
    final id = result.out.trim();
    expect(result.out, '$id\n');
    return sessionIn(dir, id);
  }

  test('nanoflow check passes the graph of the example', () async {
    final dir = copyExample();
    final result = await nanoflow([
      'check',
      '--',
      ...dartRun('graph.dart'),
    ], dir: dir);
    expect(result.code, 0, reason: '${result.out}${result.err}');
    expect(result.out, isEmpty);
  });

  test('nanoflow run drives the example to its end: inspect finds a '
      'problem, fix fixes it, and the accepted change splits into publish '
      'and notify', () async {
    final session = await runExample(copyExample(), exampleInput);

    final graph = session.session.graph;
    final nodes = graph['nodes']! as Map<String, Object?>;
    expect(graph['start'], 'collect');
    expect(nodes.keys, [
      'collect',
      'isEmpty',
      'inspect',
      'verdict',
      'fix',
      'publish',
      'notify',
      'discard',
    ]);
    for (final node in nodes.values.cast<Map<String, Object?>>()) {
      expect(node['command'] ?? node['decide'], matches(r'^graph\.dart:\d+$'));
    }
    expect((nodes['verdict']! as Map<String, Object?>)['then'], {
      'accepted': ['publish', 'notify'],
      'returned': 'fix',
    });

    final [root, ...children] = await session.runs();
    expect(root.parentId, isNull);
    expect(await journal(session, root.id), [
      'run-started collect',
      for (final node in [
        'collect',
        'isEmpty',
        'inspect',
        'verdict',
        'fix',
        'inspect',
        'verdict',
      ]) ...['step-started $node', 'step-finished 0'],
      'run-split',
    ]);
    final steps = await session.steps(root.id);
    expect(await session.documentValue(steps.first.inputId!), {
      'branch': 'parseConfig',
    });
    const before = {'id': 'parseConfig', 'path': 'lib/parseConfig.dart'};
    const after = {'id': 'parseConfig', 'path': 'lib/parse_config.dart'};
    const accepted = {'change': after, 'findings': <String>[]};
    expect(
      [for (final step in steps) await session.documentValue(step.outputId!)],
      [
        before,
        false,
        {
          'change': before,
          'findings': ['lib/parseConfig.dart: file names are lower_snake_case'],
        },
        'returned',
        after,
        accepted,
        'accepted',
      ],
    );

    expect(children, hasLength(2));
    final logs = <String, String>{};
    for (final child in children) {
      expect(child.parentId, root.id);
      final [step] = await session.steps(child.id);
      final node = (await journal(session, child.id)).first.split(' ').last;
      expect(await journal(session, child.id), [
        'run-started $node',
        'step-started $node',
        'step-finished 0',
        'run-finished',
      ]);
      expect(await session.documentValue(step.inputId!), accepted);
      logs[node] = logOf(session, step);
    }
    expect(logs, {
      'publish': 'published lib/parse_config.dart\n',
      'notify': 'parseConfig: accepted\n',
    });
  });

  test('a branch without a name: isEmpty sends the run to discard', () async {
    final session = await runExample(copyExample(), '{"branch": ""}');
    final [run] = await session.runs();
    expect(await journal(session, run.id), [
      'run-started collect',
      for (final node in ['collect', 'isEmpty', 'discard']) ...[
        'step-started $node',
        'step-finished 0',
      ],
      'run-finished',
    ]);
    final [collect, isEmpty, discard] = await session.steps(run.id);
    const nothing = {'id': '', 'path': ''};
    expect(await session.documentValue(collect.outputId!), nothing);
    expect(await session.documentValue(isEmpty.outputId!), true);
    expect(await session.documentValue(discard.inputId!), nothing);
    expect(discard.outputId, isNull);
    expect(logOf(session, discard), 'nothing to review\n');
  });

  test('nanoflow_reader, following the example while the engine runs it, '
      'ends with what the store reads back', () async {
    final dir = copyExample();
    // `runs` does not exist yet: the feed starts once the engine makes it.
    final feed = Feed(
      FsReader(
        runsDir: p.join(dir, runsDirName),
        graphName: 'graph',
        pollInterval: const Duration(milliseconds: 20),
      ),
    );
    final session = await runExample(dir, exampleInput);
    await feed.settle();
    final changes = feed.changes;

    expect(feed.errors, isEmpty);
    expect(changes.whereType<SessionAdded>(), [SessionAdded(session.session)]);
    final runs = await session.runs();
    expect(
      changes.whereType<RunAdded>(),
      unorderedEquals(runs.map(RunAdded.new)),
    );

    // A step comes once. One that got its output while the reader was
    // looking came without it first, and then changed.
    var stepChanges = 0;
    for (final run in runs) {
      for (final step in await session.steps(run.id)) {
        final given = [
          for (final change in changes)
            if (change
                case StepAdded(step: Step(:final id)) ||
                    StepChanged(step: Step(:final id))
                when id == step.id)
              change,
        ];
        final withoutOutput = Step(
          id: step.id,
          runId: step.runId,
          inputId: step.inputId,
          outputId: null,
          log: step.log,
        );
        expect(
          given,
          anyOf(
            equals([StepAdded(step)]),
            equals([StepAdded(withoutOutput), StepChanged(step)]),
          ),
          reason: 'step ${step.id}',
        );
        stepChanges += given.length;
      }
    }
    expect(
      changes.where((c) => c is StepAdded || c is StepChanged),
      hasLength(stepChanges),
    );

    var events = 0;
    for (final run in runs) {
      final journal = await session.events(run.id);
      expect([
        for (final change in changes)
          if (change case EventAdded(event: KnownEvent(:final runId))
              when runId == run.id)
            change.event,
      ], journal);
      events += journal.length;
    }
    expect(changes.whereType<EventAdded>(), hasLength(events));

    final documents = [
      for (final file in Directory(
        p.join(session.dir, documentsDirName),
      ).listSync())
        p.basenameWithoutExtension(file.path),
    ];
    expect(
      changes.whereType<DocumentAdded>(),
      unorderedEquals([
        for (final id in documents)
          DocumentAdded(sessionId: session.session.id, documentId: id),
      ]),
    );
    for (final id in documents) {
      expect(
        await feed.reader.documentValue(session.session.id, id),
        await session.documentValue(id),
      );
    }
    expect(changes.whereType<LogCorrupted>(), isEmpty);
  });
}
