// examples/review run as an app is run: with `dart run`, and compiled and
// stamped; stopped with Ctrl+C, or killed while a reader watches the owner
// of its session, and taken on again.
@Timeout(Duration(seconds: 90))
library;

import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_process/nanoflow_process.dart';
import 'package:nanoflow_reader/nanoflow_reader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/feed.dart';
import 'support/programs.dart';
import 'support/wait.dart';

/// The example package.
final String example = p.join(repoRoot, 'examples', 'review');

/// The path of the graph file of the example's review graph, from the
/// package root.
const reviewFile = 'lib/review.graph.json';

/// The graph file of the example's review graph, as the repository has it.
Map<String, Object?> exampleGraph() => readJson(p.join(example, reviewFile));

/// The snapshot a session of review keeps of the graph file [file] — by
/// default the repository's —: the graph put together with its subgraphs,
/// of which it has none.
Map<String, Object?> snapshotOf([Map<String, Object?>? file]) =>
    assembleGraphFile(reviewFile, {
      reviewFile: OneGraphFile.fromJson(file ?? exampleGraph()),
    })!.toJson();

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

/// For each node of the example's review graph, a piece of the one line of
/// `lib/review.dart` where the graph first names it: the node's place.
/// publish and notify are named side by side, on one line.
const nodeLines = {
  'collect': 'Graph.start(collect)',
  'discard': 'Empty(:final branch) => discard(branch)',
  'inspect': 'Found(:final change) => inspect(change)',
  'publish': '{publish(r), notify(r)}',
  'notify': '{publish(r), notify(r)}',
  'fix': ': fix(r)',
  'report': '=> report(sent)',
};

/// Copies what the library and describe read of the example — its sources,
/// its graph file next to them and the name of its package — into [dir].
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
/// `parseConfig`, finished; each node's effect at the node's place in the
/// graph, the fix done, report the join of publish and notify; [restarted]
/// effects started twice — run again in their record after a crash —,
/// collect not among them, and every other once. When given, [graph] is the
/// graph file the session recorded and [codes] the hashes of the code it ran.
Future<void> expectReviewed(
  String projectDir,
  String sessionId, {
  int restarted = 0,
  Map<String, Object?>? graph,
  List<String>? codes,
}) async {
  final session = await sessionIn(projectDir, sessionId);
  expect(session.session.workflow, 'review');
  if (graph != null) expect(session.session.graph, graph);
  expect(await session.documentValue(session.session.inputId!), 'parseConfig');

  final state = replaySession(await session.events());
  expect(state.status, SessionStatus.finished);
  if (codes != null) expect(state.codes, codes);

  final effects = await session.effects();
  final names = [for (final effect in effects) effect.name];
  expect(names.take(4), ['collect', 'inspect', 'fix', 'inspect']);
  expect(names.skip(4).take(2), unorderedEquals(['publish', 'notify']));
  expect(names.last, 'report');
  expect(names, hasLength(7));
  for (final effect in effects) {
    expect(effect.place, placeOf(nodeLines[effect.name]!), reason: effect.name);
  }
  final starts = {
    for (final effect in state.effects) effect.effectId: effect.starts,
  };
  expect(starts[effects.first.id], 1);
  expect([for (final effect in effects) starts[effect.id]]..sort(), [
    for (var i = 0; i < effects.length - restarted; i++) 1,
    for (var i = 0; i < restarted; i++) 2,
  ]);
  // What each node gave is in the journal, as JSON.
  const before = {'id': 'parseConfig', 'path': 'lib/parseConfig.dart'};
  const after = {'id': 'parseConfig', 'path': 'lib/parse_config.dart'};
  Future<Object?> outputOf(int i) =>
      session.documentValue(effects[i].outputId!);
  expect(await outputOf(0), before);
  expect(await outputOf(1), {
    'change': before,
    'findings': ['lib/parseConfig.dart: file names are lower_snake_case'],
  });
  expect(await outputOf(2), after);
  expect(await outputOf(3), {'change': after, 'findings': <Object?>[]});
  expect(
    {
      for (final i in [4, 5]) names[i]: await outputOf(i),
    },
    {
      'publish': 'published lib/parse_config.dart',
      'notify': 'parseConfig: accepted',
    },
  );
  expect(await outputOf(6), isNull);
  String logByName(String name) =>
      logOf(session, effects.singleWhere((e) => e.name == name))!;
  expect(logByName('publish'), 'published lib/parse_config.dart\n');
  expect(logByName('notify'), 'parseConfig: accepted\n');
  // The join gave report the outputs of publish and notify, in the order of
  // the join.
  expect(
    logByName('report'),
    'published lib/parse_config.dart; parseConfig: accepted\n',
  );
}

/// An `sh` that, put before the real one on `PATH`, stands in for inspect's
/// check and holds it: it makes the file [checking] to tell the check runs,
/// waits until there is the file [go], and then runs the real check.
final class HeldCheck {
  HeldCheck() {
    final sh = File(p.join(dir, 'sh'))
      ..writeAsStringSync(
        "#!/bin/sh\n: > '$checking'\n"
        "until [ -e '$go' ]; do sleep 0.05; done\n"
        'exec /bin/sh "\$@"\n',
      );
    expect(Process.runSync('chmod', ['+x', sh.path]).exitCode, 0);
  }

  /// The directory of the `sh`, deleted after the test.
  final String dir = tempDir();

  /// Made each time the check starts.
  String get checking => p.join(dir, 'checking');

  /// Lets every check, waiting or to come, run.
  String get go => p.join(dir, 'go');

  /// What a program whose checks are held adds to its environment.
  Map<String, String> get environment => {
    'PATH': '$dir:${Platform.environment['PATH']}',
  };
}

void main() {
  test('its graph file is the README review graph, read from its code, its '
      'nodes at their first mention in it', () {
    final graph = exampleGraph();
    expect(graph['package'], 'review_example');
    expect(graph['warnings'], isEmpty);
    expect(graph['sources'], {
      for (final path in ['lib/change.dart', 'lib/review.dart'])
        path: sourceHash(File(p.join(example, path)).readAsBytesSync()),
    });
    Map<String, Object?> effect(String id, String name, String doc) => {
      'id': id,
      'kind': 'effect',
      'name': name,
      'place': placeOf(nodeLines[name]!),
      'doc': doc,
    };
    Map<String, Object?> edge(String? from, String? to, [String? label]) => {
      'from': from,
      'to': to,
      'label': label,
    };
    expect(
      {
        for (final key in ['name', 'place', 'doc', 'body']) key: graph[key],
      },
      {
        'name': 'review',
        'place': placeOf('final review = '),
        'doc': 'Reviews the change of a branch.',
        'body': {
          'nodes': [
            // collect's route decides by its switch first: collect's own
            // exits, no fork; so is inspect's ?:, its condition and else.
            effect(
              '1',
              'collect',
              'The change of the branch, or Empty when it changes nothing.',
            ),
            effect(
              '2',
              'discard',
              'Ends the review of a branch that changes nothing.',
            ),
            effect(
              '3',
              'inspect',
              "Checks the name of the change's file with a program, as a "
                  'reviewer\nsuch as `claude -p` would be run.',
            ),
            effect('4', 'publish', 'Puts the change out.'),
            effect('5', 'notify', "Tells the branch's author it is accepted."),
            effect(
              '6',
              'fix',
              'Renames the file to lower_snake_case, for inspect to check '
                  'again.',
            ),
            effect(
              '7',
              'report',
              'Sums up the review once the change is out and the author is '
                  'told.',
            ),
          ],
          'edges': [
            edge(null, '1'),
            edge('1', '2', 'Empty'),
            edge('1', '3', 'Found'),
            edge('2', null),
            // publish and notify side by side.
            edge('3', '4', 'r.findings.isEmpty'),
            edge('3', '5', 'r.findings.isEmpty'),
            edge('3', '6', 'else'),
            // The join of publish and notify goes to report.
            edge('4', '7'),
            edge('5', '7'),
            edge('6', '3'),
            edge('7', null),
          ],
        },
      },
    );
  });

  group('dart run', () {
    late String dir;
    late String packages;

    setUp(() {
      dir = tempDir();
      copyExample(dir);
      packages = p.join(repoRoot, '.dart_tool', 'package_config.json');
    });

    Future<Running> start(List<String> args, {HeldCheck? check}) =>
        Running.start(
          dart,
          [
            'run',
            '--packages=$packages',
            p.join(dir, 'bin', 'main.dart'),
            ...args,
          ],
          dir: dir,
          environment: check?.environment,
        );

    test('a branch whose file name needs a fix is reviewed to the end, with '
        'the graph file and the fingerprint of the sources', () async {
      final running = await start(['parseConfig']);
      final id = await running.firstLine();
      expect(await running.exitCode, 0, reason: '${running.err}');
      expect(running.lines, [id]);
      expect('${running.err}', isEmpty);
      await expectReviewed(
        dir,
        id,
        graph: snapshotOf(),
        codes: [exampleGraph()['fingerprint']! as String],
      );
    });

    test('a branch that changes nothing goes to discard, its Empty written '
        'to the journal as the branch', () async {
      final running = await start(['']);
      final id = await running.firstLine();
      expect(await running.exitCode, 0, reason: '${running.err}');
      final session = await sessionIn(dir, id);
      final state = replaySession(await session.events());
      expect(state.status, SessionStatus.finished);
      final effects = await session.effects();
      expect(
        [for (final effect in effects) effect.name],
        ['collect', 'discard'],
      );
      expect(await session.documentValue(effects.first.outputId!), {
        'branch': '',
      });
      expect(logOf(session, effects.last), 'nothing to review\n');
    });

    test('killed with SIGKILL in a node, --resume takes the nodes that '
        'finished from the journal and ends it', () async {
      final check = HeldCheck();
      final first = await start(['parseConfig'], check: check);
      final id = await first.firstLine();
      await waitFor(
        'inspect to run its check',
        File(check.checking).existsSync,
      );
      first.process.kill(ProcessSignal.sigkill);
      expect(await first.exitCode, -ProcessSignal.sigkill.signalNumber);

      File(check.go).createSync();
      final resumed = await start(['--resume', id], check: check);
      expect(await resumed.exitCode, 0, reason: '${resumed.err}');
      expect(resumed.lines, [id]);
      await expectReviewed(dir, id, restarted: 1);
    });
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

      final graph = readJson(p.join(build, reviewFile));
      expect((graph['builds']! as Map)['review'], binaryHash());
      const noBuilds = {'builds': <String, Object?>{}};
      expect({...graph, ...noBuilds}, {...exampleGraph(), ...noBuilds});
      await expectReviewed(
        build,
        id,
        graph: snapshotOf(graph),
        codes: [binaryHash()],
      );
    });

    test('Ctrl+C stops the session, which no other process can take on '
        'while it runs; exit 130, and --resume ends it', () async {
      final check = HeldCheck();
      final first = await Running.start(binary, [
        'parseConfig',
      ], environment: check.environment);
      final id = await first.firstLine();
      await waitFor(
        'inspect to run its check',
        File(check.checking).existsSync,
      );

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
        'effect-started',
        'effect-finished',
        'effect-started',
      ]);

      final resumed = await run(binary, ['--resume', id]);
      expect(resumed, (code: 0, out: '$id\n', err: ''));
      // The stopped inspect ran again in its record.
      await expectReviewed(
        build,
        id,
        restarted: 1,
        codes: [binaryHash(), binaryHash()],
      );
    });

    test('killed with SIGKILL in a node: the reader tells the owner of its '
        'session gone within 5 s; --resume tells the new owner alive, then '
        'session-finished, and nothing of the owner after it', () async {
      final check = HeldCheck();
      final first = await Running.start(binary, [
        'parseConfig',
      ], environment: check.environment);
      final id = await first.firstLine();
      await waitFor(
        'inspect to run its check',
        File(check.checking).existsSync,
      );

      final processes = MacProcesses();
      addTearDown(processes.close);
      Owner ownerOf(Running program) {
        final pid = program.process.pid;
        return Owner(pid: pid, started: processes.startOf(pid));
      }

      final firstOwner = ownerOf(first);
      // The reader as the UI makes it: it takes the adapter of this OS, and
      // closes it when the feed is cancelled at the end of the test.
      final feed = Feed(FsReader(runsDir: runsDirOf(build)));
      await feed.given(
        OwnerChanged(sessionId: id, owner: firstOwner, alive: true),
      );

      final killed = Stopwatch()..start();
      first.process.kill(ProcessSignal.sigkill);
      await feed.given(
        OwnerChanged(sessionId: id, owner: firstOwner, alive: false),
      );
      expect(killed.elapsed, lessThan(const Duration(seconds: 5)));
      expect(await first.exitCode, -ProcessSignal.sigkill.signalNumber);

      // Its check is held too, so that the session cannot end before the
      // reader has looked at the new owner.
      final resumed = await Running.start(binary, [
        '--resume',
        id,
      ], environment: check.environment);
      final resumedOwner = ownerOf(resumed);
      expect(resumedOwner.pid, isNot(firstOwner.pid));
      await feed.given(
        OwnerChanged(sessionId: id, owner: resumedOwner, alive: true),
      );
      File(check.go).createSync();
      expect(await resumed.exitCode, 0, reason: '${resumed.err}');
      expect(resumed.lines, [id]);
      await feed.givenWhere(
        id,
        'session-finished',
        (change) => change is EventAdded && change.event is SessionFinished,
      );
      // Settled, so that an owner-changed after it, had one come, is below.
      await feed.settle();

      expect(feed.errors, isEmpty);
      final ofSession = [
        for (final change in feed.of(id))
          if (change is OwnerChanged || change is EventAdded) change,
      ];
      expect(ofSession.whereType<OwnerChanged>(), [
        OwnerChanged(sessionId: id, owner: firstOwner, alive: true),
        OwnerChanged(sessionId: id, owner: firstOwner, alive: false),
        OwnerChanged(sessionId: id, owner: resumedOwner, alive: true),
      ]);
      expect(
        ofSession.last,
        isA<EventAdded>().having(
          (change) => change.event,
          'event',
          isA<SessionFinished>(),
        ),
      );
    }, testOn: 'mac-os');
  });
}
