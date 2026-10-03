// examples/review run as an app is run: with `dart run`, and compiled and
// stamped; stopped with Ctrl+C and taken on again.
@Timeout(Duration(seconds: 90))
library;

import 'dart:io';

import 'package:nanoflow/nanoflow.dart' show SessionBusyException;
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/programs.dart';
import 'support/wait.dart';

/// The example package.
final String example = p.join(repoRoot, 'examples', 'review');

/// The example's graph file, as the repository has it.
Map<String, Object?> exampleGraph() => readJson(p.join(example, graphFileName));

/// The id of the example's workflow in its graph file.
const reviewId = 'lib/review.dart#review';

/// `lib/review.dart:<line>` of the one line of the example's
/// `lib/review.dart` that holds [code].
String placeOf(String code) {
  final lines = File(p.join(example, 'lib', 'review.dart')).readAsLinesSync();
  final found = [
    for (final (i, line) in lines.indexed)
      if (line.contains(code)) i + 1,
  ];
  expect(found, hasLength(1), reason: code);
  return 'lib/review.dart:${found.single}';
}

/// Copies what the library and describe read of the example — its sources,
/// its graph file and the name of its package — into [dir].
///
/// The copy gives a project directory only: where `runs/` goes, the graph
/// file, the package's name and the sources the code hash is taken of. The
/// code that runs is the repository's: `package:review_example` resolves to
/// `examples/review/lib/` through the workspace's package config, not to the
/// copy's `lib/`, and only the copy's `bin/main.dart`, as the script, is
/// run from the copy.
///
/// The copy's pubspec has the name and the SDK alone: outside the
/// workspace, the example's `resolution: workspace` would make `dart run`
/// complain.
void copyExample(String dir) {
  Directory(dir).createSync(recursive: true);
  File(
    p.join(dir, 'pubspec.yaml'),
  ).writeAsStringSync('name: review_example\nenvironment:\n  sdk: ^3.13.0\n');
  File(p.join(example, graphFileName)).copySync(p.join(dir, graphFileName));
  for (final sources in ['lib', 'bin']) {
    for (final file in Directory(
      p.join(example, sources),
    ).listSync(recursive: true).whereType<File>()) {
      final copy = File(p.join(dir, p.relative(file.path, from: example)));
      copy.parent.createSync(recursive: true);
      file.copySync(copy.path);
    }
  }
}

/// Checks the session [sessionId] in [projectDir]: a review of the branch
/// `parseConfig`, whose file name inspect finds wrong once, run from its
/// start to its end in one go, with [graph] as the graph file and [code] as
/// the hash of the code it ran.
Future<void> expectReviewed(
  String projectDir,
  String sessionId, {
  required Map<String, Object?> graph,
  required String code,
}) async {
  final session = await sessionIn(projectDir, sessionId);
  expect(session.session.workflow, 'review');
  expect(session.session.graph, graph);
  expect(await session.documentValue(session.session.inputId!), 'parseConfig');

  final state = replaySession(await session.events());
  expect(state.status, SessionStatus.finished);
  expect(state.codes, [code]);
  expect(await session.documentValue(state.outputId!), isNull);

  final steps = await session.steps();
  expect(
    [for (final step in steps) step.name],
    ['collect', 'inspect', 'fix', 'inspect', 'publish', 'notify'],
  );
  expect(
    [for (final step in state.steps) (step.stepId, step.status, step.starts)],
    unorderedEquals([
      for (final step in steps) (step.id, StepStatus.finished, 1),
    ]),
  );
  const before = {'id': 'parseConfig', 'path': 'lib/parseConfig.dart'};
  const after = {'id': 'parseConfig', 'path': 'lib/parse_config.dart'};
  expect(
    [for (final step in steps) await session.documentValue(step.outputId!)],
    [
      before,
      {
        'change': before,
        'findings': ['lib/parseConfig.dart: file names are lower_snake_case'],
      },
      after,
      {'change': after, 'findings': <Object?>[]},
      null,
      null,
    ],
  );
  expect(
    [for (final step in steps) logOf(session, step)],
    [
      null,
      null,
      null,
      null,
      'published lib/parse_config.dart\n',
      'parseConfig: accepted\n',
    ],
  );

  // Each step is where its node is in the graph.
  final function = (graph['functions']! as Map)[reviewId] as Map;
  final nodes = ((function['body']! as Map)['nodes']! as List)
      .cast<Map<String, Object?>>();
  for (final step in steps) {
    expect(
      step.place,
      nodes.singleWhere((node) => node['name'] == step.name)['place'],
      reason: step.name,
    );
  }
}

void main() {
  test('its graph file is the README review graph, read from its code', () {
    final graph = exampleGraph();
    expect(graph['package'], 'review_example');
    expect(graph['workflows'], [reviewId]);
    expect(graph['warnings'], isEmpty);
    Map<String, Object?> step(String id, String name) => {
      'id': id,
      'kind': 'step',
      'name': name,
      'place': placeOf("f.step('$name'"),
    };
    Map<String, Object?> fork(String id, String label) => {
      'id': id,
      'kind': 'fork',
      'label': label,
      'place': placeOf(label),
    };
    Map<String, Object?> edge(String? from, String? to, [String? label]) => {
      'from': from,
      'to': to,
      'label': label,
    };
    expect(graph['functions'], {
      reviewId: {
        'name': 'review',
        'place': placeOf('Future<void> review('),
        'body': {
          'nodes': [
            step('1', 'collect'),
            fork('2', 'change.path.isEmpty'),
            step('3', 'discard'),
            step('4', 'inspect'),
            fork('5', 'report.findings.isEmpty'),
            step('6', 'publish'),
            step('7', 'notify'),
            step('8', 'fix'),
          ],
          'edges': [
            edge(null, '1'),
            edge('1', '2'),
            edge('2', '3', 'true'),
            edge('2', '4', 'false'),
            edge('3', null),
            edge('4', '5'),
            // publish and notify side by side.
            edge('5', '6', 'true'),
            edge('5', '7', 'true'),
            edge('5', '8', 'false'),
            edge('6', null),
            edge('7', null),
            edge('8', '4'),
          ],
        },
      },
    });
  });

  test('dart run: a branch whose file name needs a fix is reviewed to the '
      'end, with the graph file and the fingerprint of the sources', () async {
    // A copy, so that its sessions go to runs/ in the copy.
    final dir = tempDir();
    copyExample(dir);
    final packages = p.join(repoRoot, '.dart_tool', 'package_config.json');

    final outcome = await run(dart, [
      'run',
      '--packages=$packages',
      p.join(dir, 'bin', 'main.dart'),
      'parseConfig',
    ], dir: dir);
    expect(outcome.code, 0, reason: outcome.err);
    final id = outcome.out.trim();
    expect(outcome, (code: 0, out: '$id\n', err: ''));

    final graph = exampleGraph();
    await expectReviewed(
      dir,
      id,
      graph: graph,
      code: graph['fingerprint']! as String,
    );
  });

  group('compiled', () {
    // The binary, compiled and stamped once: its graph file is next to it.
    late String build;
    late String binary;

    setUpAll(() async {
      final dir = tempDir();
      build = p.join(dir, 'build');
      binary = p.join(build, 'review');
      Directory(build).createSync();
      await compile(p.join(example, 'bin', 'main.dart'), binary);
      // A copy of the package is stamped: the example's own graph file
      // keeps no build of a test.
      final package = p.join(dir, 'package');
      copyExample(package);
      final stamped = await run(dart, [
        'run',
        'nanoflow_describe',
        '--package',
        package,
        'stamp',
        binary,
      ], dir: example);
      expect(stamped.code, 0, reason: '${stamped.out}${stamped.err}');
    });

    String binaryHash() => bytesHash(File(binary).readAsBytesSync());

    test('a branch whose file name needs a fix is reviewed to the end, with '
        'the graph file next to the binary, whose builds have the hash of '
        'the binary, the code', () async {
      final outcome = await run(binary, ['parseConfig']);
      final id = outcome.out.trim();
      expect(outcome, (code: 0, out: '$id\n', err: ''));

      final graph = readJson(p.join(build, graphFileName));
      expect((graph['builds']! as Map)['review'], binaryHash());
      const noBuilds = {'builds': <String, Object?>{}};
      expect({...graph, ...noBuilds}, {...exampleGraph(), ...noBuilds});
      await expectReviewed(build, id, graph: graph, code: binaryHash());
    });

    test('Ctrl+C stops the session, which no other process can take on '
        'while it runs; exit 130, and --resume ends it', () async {
      // An `sh` before the real one on PATH stands in for inspect's check:
      // it tells it runs, then waits until it is stopped.
      final fake = tempDir();
      final checking = p.join(fake, 'checking');
      final sh = File(p.join(fake, 'sh'))
        ..writeAsStringSync(
          "#!/bin/sh\n: > '$checking'\nwhile :; do sleep 0.05; done\n",
        );
      expect(Process.runSync('chmod', ['+x', sh.path]).exitCode, 0);

      final first = await Running.start(
        binary,
        ['parseConfig'],
        environment: {'PATH': '$fake:${Platform.environment['PATH']}'},
      );
      final id = await first.firstLine();
      await waitFor('inspect to run its check', File(checking).existsSync);

      expect(await run(binary, ['--resume', id]), (
        code: 1,
        out: '',
        err: '${SessionBusyException(id)}\n',
      ));

      expect(first.process.kill(ProcessSignal.sigint), isTrue);
      expect(await first.exitCode, 130);
      expect(first.lines, [id]);
      expect('${first.err}', isEmpty);
      final stopped = await sessionIn(build, id);
      expect(await eventNames(stopped), [
        'session-started',
        'step-started',
        'step-finished',
        'step-started',
      ]);

      final resumed = await run(binary, ['--resume', id]);
      expect(resumed, (code: 0, out: '$id\n', err: ''));
      final session = await sessionIn(build, id);
      final state = replaySession(await session.events());
      expect(state.status, SessionStatus.finished);
      expect(state.codes, [binaryHash(), binaryHash()]);
      final steps = await session.steps();
      expect(
        [for (final step in steps) step.name],
        ['collect', 'inspect', 'fix', 'inspect', 'publish', 'notify'],
      );
      // The stopped inspect ran again in its record.
      expect(
        {for (final step in state.steps) step.stepId: step.starts},
        {for (final (i, step) in steps.indexed) step.id: i == 1 ? 2 : 1},
      );
    });
  });
}
