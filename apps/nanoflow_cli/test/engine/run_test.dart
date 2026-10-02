import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_cli/nanoflow_cli.dart';
import 'package:nanoflow_cli/src/engine/engine.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fake_program.dart';
import '../support/helpers.dart';
import '../support/sessions.dart';

/// A run's exit code and journal.
typedef Journal = ({int code, List<String> journal});

/// Checks that [actual] has [code] and [journal].
void expectJournal(
  Journal actual,
  int code,
  List<String> journal, {
  String? reason,
}) {
  expect(actual.code, code, reason: reason);
  expect(actual.journal, journal, reason: reason);
}

/// Runs a graph that starts at a fork with the `then` and `else` of [fork],
/// whose script prints [outcome]; [workers] are the nodes it leads to, which
/// do nothing.
Future<Journal> decide(
  Map<String, Object?> fork,
  String outcome, {
  List<String> workers = const [],
}) async {
  final (:code, err: _, :session) = await runGraph(
    {
      'start': 'fork',
      'nodes': {
        'fork': {'decide': 'fork', ...fork},
        for (final worker in workers) worker: {'command': worker},
      },
    },
    nodes: {
      'fork': "echo '$outcome'",
      for (final worker in workers) worker: 'true',
    },
  );
  return (
    code: code,
    journal: await journal(session, (await onlyRun(session)).id),
  );
}

/// The journal of a run of [decide] that goes from the fork to [node].
List<String> forkThen(String node) => [
  'run-started fork',
  'step-started fork',
  'step-finished 0',
  'step-started $node',
  'step-finished 0',
  'run-finished',
];

/// The journal of a run of [decide] that ends at the fork.
const forkEnded = [
  'run-started fork',
  'step-started fork',
  'step-finished 0',
  'run-finished',
];

void main() {
  group('a chain of workers', () {
    test('runs each node with the data of the one before', () async {
      final graph = {
        'start': 'collect',
        'nodes': {
          'collect': {
            'command': 'collect',
            'in': object,
            'out': object,
            'then': 'inspect',
          },
          'inspect': {
            'command': 'inspect',
            'in': object,
            'out': object,
            'then': 'publish',
          },
          'publish': {'command': 'publish', 'in': object},
        },
      };
      final (:code, err: _, :session) = await runGraph(
        graph,
        nodes: {
          'collect':
              r'''IFS= read -r line; printf '{"request": %s}\n' "$line"''',
          'inspect':
              r'''IFS= read -r line; printf '{"inspected": %s}\n' "$line"''',
          'publish': logInput,
        },
        stdin: '{\n  "branch": "main",\n  "note": "a\\nb"\n}\n',
      );
      expect(code, 0);
      expect(session.session.graph, graph);
      final run = await onlyRun(session);
      expect(run.parentId, isNull);
      expect(await journal(session, run.id), [
        'run-started collect',
        'step-started collect',
        'step-finished 0',
        'step-started inspect',
        'step-finished 0',
        'step-started publish',
        'step-finished 0',
        'run-finished',
      ]);
      final [collect, inspect, publish] = [
        for (final s in await stepsOf(session, run.id)) s.step,
      ];
      const request = {'branch': 'main', 'note': 'a\nb'};
      expect(await session.documentValue(collect.inputId!), request);
      expect(await session.documentValue(collect.outputId!), {
        'request': request,
      });
      expect(inspect.inputId, collect.outputId);
      expect(await session.documentValue(inspect.outputId!), {
        'inspected': {'request': request},
      });
      expect(publish.inputId, inspect.outputId);
      expect(publish.outputId, isNull);
      // The input comes as one line of compact JSON.
      expect(
        logOf(session, publish),
        '{"inspected":{"request":{"branch":"main","note":"a\\nb"}}}\n',
      );
      for (final step in [collect, inspect, publish]) {
        final finish = await finishOf(session, run.id, step.id);
        expect(finish.outputId, step.outputId);
      }
    });

    test('a worker with an empty list for then ends the run', () async {
      final (:code, err: _, :session) = await runGraph(
        {
          'start': 'a',
          'nodes': {
            'a': {'command': 'a', 'then': <String>[]},
          },
        },
        nodes: {'a': 'true'},
      );
      expect(code, 0);
      expect(await journal(session, (await onlyRun(session)).id), [
        'run-started a',
        'step-started a',
        'step-finished 0',
        'run-finished',
      ]);
    });

    test('the session id is printed before the first step ends', () async {
      final fake = FakeProgram(
        {
          'start': 'a',
          'nodes': {
            'a': {'command': 'a'},
          },
        },
        nodes: {'a': waitForFile('id.printed')},
      );
      final out = _OnData(
        () => File(p.join(fake.dir, 'id.printed')).createSync(),
      );
      final stdout = IOSink(out);
      final code = await runCli(
        ['run', '--', fake.path],
        stdin: const Stream.empty(),
        stdout: stdout,
        stderr: IOSink(Capture()),
      );
      await stdout.close();
      expect(code, 0);
      expect(out.text, matches(RegExp(r'^[0-9a-f-]{36}\n$')));
    });

    test('the sessions are kept next to a graph file given relative to the '
        'current directory', () async {
      final fake = FakeProgram(
        {
          'start': 'a',
          'nodes': {
            'a': {'command': 'a'},
          },
        },
        nodes: {'a': 'true'},
        relativeFile: true,
      );
      final result = await nanoflow(['run', '--', fake.path]);
      expect(result.code, 0);
      await onlySession(fake, result);
    });
  });

  group('if', () {
    const ifElse = {'then': 'yes', 'else': 'no'};

    test('true goes to then', () async {
      expectJournal(
        await decide(ifElse, 'true', workers: ['yes', 'no']),
        0,
        forkThen('yes'),
      );
    });

    test('anything but true goes to else', () async {
      for (final outcome in ['false', '"true"', '1', 'null']) {
        expectJournal(
          await decide(ifElse, outcome, workers: ['yes', 'no']),
          0,
          forkThen('no'),
          reason: outcome,
        );
      }
    });

    test('anything but true without else ends the run', () async {
      expectJournal(
        await decide({'then': 'yes'}, 'false', workers: ['yes']),
        0,
        forkEnded,
      );
    });

    test('an else that is an empty list ends the run', () async {
      expectJournal(
        await decide(
          {'then': 'yes', 'else': <String>[]},
          'false',
          workers: ['yes'],
        ),
        0,
        forkEnded,
      );
    });
  });

  group('switch', () {
    const cases = {
      'then': {'accepted': 'publish', 'returned': 'fix'},
    };

    test('an outcome that is a key goes to its target', () async {
      expectJournal(
        await decide(
          {...cases, 'else': 'other'},
          '"returned"',
          workers: ['publish', 'fix', 'other'],
        ),
        0,
        forkThen('fix'),
      );
    });

    test('the outcome is kept as the output of the fork step', () async {
      final (:code, err: _, :session) = await runGraph(
        {
          'start': 'fork',
          'nodes': {
            'fork': {'decide': 'fork', ...cases},
            'publish': {'command': 'publish'},
            'fix': {'command': 'fix'},
          },
        },
        nodes: {'fork': 'echo \'  "accepted"\'', 'publish': 'true'},
      );
      expect(code, 0);
      final run = await onlyRun(session);
      final fork = (await session.steps(run.id)).first;
      expect(await session.documentValue(fork.outputId!), 'accepted');
      final finish = await finishOf(session, run.id, fork.id);
      expect(finish.outputId, fork.outputId);
    });

    test('an outcome that is no key goes to else', () async {
      for (final outcome in ['"maybe"', 'true', '{"accepted": 1}']) {
        expectJournal(
          await decide(
            {...cases, 'else': 'other'},
            outcome,
            workers: ['publish', 'fix', 'other'],
          ),
          0,
          forkThen('other'),
          reason: outcome,
        );
      }
    });

    test('an outcome that is no key, without else, fails the run', () async {
      final outcomes = {
        '"x"': '"x"',
        '1': '1',
        '{"a": [1, "b"]}': '{"a":[1,"b"]}',
      };
      for (final MapEntry(key: outcome, value: compact) in outcomes.entries) {
        expectJournal(
          await decide(cases, outcome, workers: ['publish', 'fix']),
          1,
          [
            'run-started fork',
            'step-started fork',
            'step-finished 0',
            'run-failed no target for outcome $compact',
          ],
          reason: outcome,
        );
      }
    });

    test('an else that is an empty list ends the run', () async {
      expectJournal(
        await decide(
          {...cases, 'else': <String>[]},
          '"x"',
          workers: ['publish', 'fix'],
        ),
        0,
        forkEnded,
      );
    });
  });

  test('data goes through forks unchanged to the next node', () async {
    final (:code, err: _, :session) = await runGraph(
      {
        'start': 'produce',
        'nodes': {
          'produce': {'command': 'produce', 'out': object, 'then': 'look'},
          'look': {'decide': 'look', 'in': object, 'then': 'skip'},
          'skip': {'decide': 'skip', 'then': 'consume'},
          'consume': {'command': 'consume', 'in': object},
        },
      },
      nodes: {
        // printf, as echo of some shells reads the backslash.
        'produce': r"""printf '%s\n' '{"text": "a\nb"}'""",
        'look': '$logInput\necho true',
        'skip': '$expectNoInput\necho true',
        'consume': logInput,
      },
    );
    expect(code, 0);
    final run = await onlyRun(session);
    final [produce, look, skip, consume] = [
      for (final s in await stepsOf(session, run.id)) s.step,
    ];
    expect(await session.documentValue(produce.outputId!), {'text': 'a\nb'});
    expect(look.inputId, produce.outputId);
    expect(skip.inputId, isNull);
    expect(consume.inputId, produce.outputId);
    expect(logOf(session, look), '{"text":"a\\nb"}\n');
    expect(logOf(session, consume), '{"text":"a\\nb"}\n');
    expect(await session.documentValue(look.outputId!), true);
    expect(await session.documentValue(skip.outputId!), true);
  });

  test('a loop back to an earlier node makes a new step', () async {
    final (:code, err: _, :session) = await runGraph(
      {
        'start': 'work',
        'nodes': {
          'work': {'command': 'work', 'out': object, 'then': 'again'},
          'again': {
            'decide': 'again',
            'in': object,
            'then': 'work',
            'else': 'finish',
          },
          'finish': {'command': 'finish', 'in': object},
        },
      },
      nodes: {
        'work': r'''
n=$(cat rounds 2>/dev/null || echo 0)
n=$((n + 1))
echo $n > rounds
echo "{\"round\": $n}"''',
        'again': '''
IFS= read -r line
[ "\$line" = '{"round":1}' ] && echo true || echo false''',
        'finish': logInput,
      },
    );
    expect(code, 0);
    final run = await onlyRun(session);
    expect(await journal(session, run.id), [
      'run-started work',
      for (final node in ['work', 'again', 'work', 'again', 'finish']) ...[
        'step-started $node',
        'step-finished 0',
      ],
      'run-finished',
    ]);
    final steps = await stepsOf(session, run.id);
    expect(
      [for (final s in steps) s.node],
      ['work', 'again', 'work', 'again', 'finish'],
    );
    expect({for (final s in steps) s.step.id}, hasLength(5));
    expect(logOf(session, steps.last.step), '{"round":2}\n');
  });

  group('a split', () {
    test('runs every child at once, each from the data of the split', () async {
      // Each child waits for the other to start: one at a time, the first
      // would give up after 5 s and fail.
      String meet(String me, String other) =>
          '$logInput\ntouch $me.here\n${waitForFile('$other.here')}';
      final (:code, err: _, :session) = await runGraph(
        {
          'start': 'a',
          'nodes': {
            'a': {
              'command': 'a',
              'out': object,
              'then': ['left', 'right'],
            },
            'left': {'command': 'left', 'in': object},
            'right': {'command': 'right', 'in': object},
          },
        },
        nodes: {
          'a': 'echo \'{"n": 1}\'',
          'left': meet('left', 'right'),
          'right': meet('right', 'left'),
        },
      );
      expect(code, 0);
      final runs = await session.runs();
      expect(runs, hasLength(3));
      final root = runs.first;
      expect(root.parentId, isNull);
      expect(await journal(session, root.id), [
        'run-started a',
        'step-started a',
        'step-finished 0',
        'run-split',
      ]);
      final output = (await session.steps(root.id)).single.outputId!;
      for (final (i, node) in ['left', 'right'].indexed) {
        final child = runs[i + 1];
        expect(child.parentId, root.id);
        expect(await journal(session, child.id), [
          'run-started $node',
          'step-started $node',
          'step-finished 0',
          'run-finished',
        ]);
        final first = (await session.steps(child.id)).single;
        expect(first.inputId, output);
        expect(logOf(session, first), '{"n":1}\n');
      }
    });

    test('carries the data to a child whose node takes none', () async {
      final (:code, err: _, :session) = await runGraph(
        {
          'start': 'a',
          'nodes': {
            'a': {
              'command': 'a',
              'out': object,
              'then': ['left', 'right'],
            },
            'left': {'decide': 'left', 'then': 'after'},
            'right': {'command': 'right'},
            'after': {'command': 'after', 'in': object},
          },
        },
        nodes: {
          'a': 'echo \'{"n": 1}\'',
          'left': '$expectNoInput\necho true',
          'right': 'true',
          'after': logInput,
        },
      );
      expect(code, 0);
      final left = await runAt(session, 'left');
      final [fork, after] = await session.steps(left.id);
      expect(fork.inputId, isNull);
      expect(await session.documentValue(after.inputId!), {'n': 1});
      expect(logOf(session, after), '{"n":1}\n');
    });

    test('a child that fails does not stop the others', () async {
      final (:code, err: _, :session) = await runGraph(
        {
          'start': 'a',
          'nodes': {
            'a': {
              'command': 'a',
              'then': ['bad', 'good'],
            },
            'bad': {'command': 'bad'},
            'good': {'command': 'good', 'then': 'more'},
            'more': {'command': 'more'},
          },
        },
        nodes: {
          'a': 'true',
          'bad': 'touch bad.done\nexit 3',
          'good': '${waitForFile('bad.done')}\nsleep 0.2',
          'more': 'true',
        },
      );
      expect(code, 1);
      expect(await journal(session, (await runAt(session, 'bad')).id), [
        'run-started bad',
        'step-started bad',
        'step-finished 3',
        'run-failed exited with code 3',
      ]);
      expect(await journal(session, (await runAt(session, 'good')).id), [
        'run-started good',
        'step-started good',
        'step-finished 0',
        'step-started more',
        'step-finished 0',
        'run-finished',
      ]);
    });
  });

  group('a step that fails', () {
    Future<({int code, List<String> journal, Step step, String log})> failing(
      Map<String, Object?> node,
      String script,
    ) async {
      final (:code, err: _, :session) = await runGraph(
        {
          'start': 'a',
          'nodes': {
            'a': {...node, 'then': 'b'},
            'b': {'command': 'b'},
          },
        },
        nodes: {'a': script, 'b': 'true'},
      );
      final run = await onlyRun(session);
      final step = (await session.steps(run.id)).first;
      expect((await finishOf(session, run.id, step.id)).outputId, isNull);
      return (
        code: code,
        journal: await journal(session, run.id),
        step: step,
        log: logOf(session, step),
      );
    }

    List<String> failed(int exitCode, String error) => [
      'run-started a',
      'step-started a',
      'step-finished $exitCode',
      'run-failed $error',
    ];

    test('a command that exits with a code other than 0', () async {
      final result = await failing({
        'command': 'a',
        'out': object,
      }, 'echo "boom" >&2\necho \'{"n": 1}\'\nexit 3');
      expect(result.code, 1);
      expect(result.journal, failed(3, 'exited with code 3'));
      expect(result.step.outputId, isNull);
      expect(result.log, 'boom\n');
    });

    test('a worker with out that prints nothing', () async {
      for (final script in ['true', 'echo "   "']) {
        final result = await failing({'command': 'a', 'out': object}, script);
        expect(result.code, 1);
        expect(result.journal, failed(0, 'printed no output'), reason: script);
        expect(result.step.outputId, isNull);
      }
    });

    test('a worker with out that prints no JSON document', () async {
      for (final script in [
        'echo "not json"',
        'echo "1 2"',
        r"printf '\377\n'",
      ]) {
        final result = await failing({'command': 'a', 'out': object}, script);
        expect(result.code, 1);
        expect(
          result.journal,
          failed(0, 'printed invalid JSON'),
          reason: script,
        );
        expect(result.step.outputId, isNull);
      }
    });

    test('a step whose program cannot start fails its run, and the others '
        'go on', () async {
      final (:code, :err, :session) = await runGraph(
        {
          'start': ['breaker', 'sibling'],
          'nodes': {
            'breaker': {'command': 'breaker', 'then': 'next'},
            'next': {'command': 'next'},
            'sibling': {'command': 'sibling'},
          },
        },
        nodes: {
          // Once the sibling's call runs, the program loses its execute
          // permission: the next call cannot start.
          'breaker':
              '${waitForFile('sibling.started')}\n'
              'chmod -x graph.sh\n'
              'touch broken',
          'sibling': 'touch sibling.started\n${waitForFile('broken')}',
          'next': 'true',
        },
      );
      expect(code, 1);
      final breaker = await runAt(session, 'breaker');
      expect(await journal(session, breaker.id), [
        'run-started breaker',
        'step-started breaker',
        'step-finished 0',
        'step-started next',
        'run-failed cannot start the graph program: Permission denied',
      ]);
      final state = replay(breaker.id, await session.events(breaker.id));
      expect(state.steps.last.status, StepStatus.failed);
      expect(await journal(session, (await runAt(session, 'sibling')).id), [
        'run-started sibling',
        'step-started sibling',
        'step-finished 0',
        'run-finished',
      ]);
      // runGraph has checked that stderr holds the event lines and nothing
      // else.
      expect(
        const LineSplitter().convert(err),
        contains(
          matches(
            '^\\d\\d:\\d\\d:\\d\\d ${breaker.id.substring(0, 4)} run-failed '
            'cannot start the graph program: Permission denied\$',
          ),
        ),
      );
    });

    test('a fork that prints nothing', () async {
      final result = await failing({'decide': 'a'}, 'true');
      expect(result.code, 1);
      expect(result.journal, failed(0, 'printed no output'));
    });
  });

  group('the command log', () {
    test('a worker without out: stdout goes to the log', () async {
      final (:code, err: _, :session) = await runGraph(
        {
          'start': 'a',
          'nodes': {
            'a': {'command': 'a', 'then': 'b'},
            'b': {'command': 'b'},
          },
        },
        nodes: {'a': 'echo "to the log"', 'b': expectNoInput},
      );
      expect(code, 0);
      final run = await onlyRun(session);
      final [a, b] = await session.steps(run.id);
      expect(logOf(session, a), 'to the log\n');
      expect(a.outputId, isNull);
      expect((await finishOf(session, run.id, a.id)).outputId, isNull);
      expect(b.inputId, isNull);
    });

    test(
      'stderr goes to the log, stdout of a worker with out does not',
      () async {
        final (:code, err: _, :session) = await runGraph(
          {
            'start': 'a',
            'nodes': {
              'a': {'command': 'a', 'out': object},
            },
          },
          nodes: {'a': 'echo "working" >&2\necho \'{"done": true}\''},
        );
        expect(code, 0);
        final a = (await session.steps((await onlyRun(session)).id)).single;
        expect(logOf(session, a), 'working\n');
        expect(await session.documentValue(a.outputId!), {'done': true});
      },
    );
  });

  group('the launch input', () {
    test(
      'every start node that takes input gets the one input document',
      () async {
        final (:code, err: _, :session) = await runGraph(
          {
            'start': ['left', 'right', 'plain'],
            'nodes': {
              'left': {'command': 'left', 'in': object},
              'right': {'command': 'right', 'in': object},
              'plain': {'command': 'plain'},
            },
          },
          nodes: {'left': logInput, 'right': logInput, 'plain': expectNoInput},
          stdin: '{"branch": "main"}',
        );
        expect(code, 0);
        final runs = await session.runs();
        expect(runs, hasLength(3));
        expect([for (final run in runs) run.parentId], [null, null, null]);
        final firsts = {
          for (final node in ['left', 'right', 'plain'])
            node: (await session.steps((await runAt(session, node)).id)).single,
        };
        final input = firsts['left']!.inputId!;
        expect(firsts['right']!.inputId, input);
        expect(firsts['plain']!.inputId, isNull);
        expect(documentsOf(session), ['$input.json']);
        expect(await session.documentValue(input), {'branch': 'main'});
        expect(logOf(session, firsts['right']!), '{"branch":"main"}\n');
      },
    );

    test('is what --input prints', () async {
      final fake = FakeProgram(
        {
          'start': 'a',
          'nodes': {
            'a': {'command': 'a', 'in': object},
          },
        },
        nodes: {'a': logInput},
        input: 'cat >/dev/null; echo \'{"branch": "checked"}\'',
      );
      final result = await nanoflow([
        'run',
        '--',
        fake.path,
      ], stdin: '{"branch": "main"}');
      expect(result.code, 0);
      final session = await onlySession(fake, result);
      final a = (await session.steps((await onlyRun(session)).id)).single;
      expect(await session.documentValue(a.inputId!), {'branch': 'checked'});
    });

    test('is not read when no start node takes input', () async {
      final fake = FakeProgram(
        {
          'start': 'a',
          'nodes': {
            'a': {'command': 'a'},
          },
        },
        nodes: {'a': expectNoInput},
        input: 'echo "--input was run" >&2; exit 1',
      );
      // Never closed: reading it to the end would never end.
      final stdin = StreamController<List<int>>();
      final result = await nanoflow([
        'run',
        '--',
        fake.path,
      ], stdinStream: stdin.stream);
      expect(result.code, 0, reason: result.err);
      expect(stdin.hasListener, isFalse);
      final session = await onlySession(fake, result);
      await expectProgress(result.err, session);
      final a = (await session.steps((await onlyRun(session)).id)).single;
      expect(a.inputId, isNull);
      expect(documentsOf(session), isEmpty);
    });

    final takesInput = {
      'start': 'a',
      'nodes': {
        'a': {'command': 'a', 'in': object},
      },
    };

    test('none on stdin: exit 2 and no session', () async {
      for (final stdin in ['', ' \n\t\n']) {
        final fake = FakeProgram(takesInput, nodes: {'a': 'true'});
        final result = await nanoflow(['run', '--', fake.path], stdin: stdin);
        expect(result, (code: 2, out: '', err: 'no input on stdin\n'));
        expect(Directory(fake.runsDir).existsSync(), isFalse);
      }
    });

    test(
      'rejected by --input: exit 2 with its reason, and no session',
      () async {
        final fake = FakeProgram(
          takesInput,
          nodes: {'a': 'true'},
          input: 'cat >/dev/null; echo "branch: missing" >&2; exit 1',
        );
        final result = await nanoflow(['run', '--', fake.path], stdin: '{}');
        expect(result, (code: 2, out: '', err: 'branch: missing\n'));
        expect(Directory(fake.runsDir).existsSync(), isFalse);
      },
    );
  });

  group('no graph to run', () {
    test(
      'a graph that does not pass check: exit 2, its errors on stderr',
      () async {
        final fake = FakeProgram(
          {
            'start': 'a',
            'nodes': {
              'a': {'command': 'a', 'then': 'b'},
              'lost': {'command': 'lost'},
            },
          },
          nodes: {'a': 'true'},
        );
        final result = await nanoflow(['run', '--', fake.path]);
        expect(result, (
          code: 2,
          out: '',
          err:
              'nodes.a.then: unknown node "b"\n'
              'nodes.lost: unreachable from start\n',
        ));
        expect(Directory(fake.runsDir).existsSync(), isFalse);
      },
    );

    test('a program that fails on --graph: exit 2', () async {
      final result = await nanoflow([
        'run',
        '--',
        script('echo "no graph here" >&2\nexit 3\n'),
      ]);
      expect(result, (
        code: 2,
        out: '',
        err:
            'no graph here\n'
            'cannot read the graph: --graph exited with code 3\n',
      ));
    });

    test('a program that prints no description: exit 2', () async {
      final result = await nanoflow([
        'run',
        '--',
        script('echo "Building..."\n'),
      ]);
      expect(result, (
        code: 2,
        out: '',
        err: 'cannot read the graph: --graph output: not JSON\n',
      ));
    });

    test('arguments that are not a command: the usage, exit 2', () async {
      const usage =
          'usage: nanoflow run [--resume <session id>] -- <graph program> '
          '[args...]\n'
          '       nanoflow check [-- <graph program> [args...]]\n';
      for (final args in [
        ['run'],
        ['run', '--'],
        ['run', 'graph.sh'],
        ['run', '--resume'],
        ['run', '--resume', newId()],
        ['run', '--resume', newId(), '--'],
        ['run', '--resume', newId(), 'graph.sh'],
        ['run', '--resume', '--', 'graph.sh'],
      ]) {
        expect(await nanoflow(args), (
          code: 2,
          out: '',
          err: usage,
        ), reason: '$args');
      }
    });
  });

  test('stderr: a line per event with the local time, the run and the '
      'details', () async {
    // runGraph checks each line against its event; here is the form.
    final (:code, :err, :session) = await runGraph(
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
      nodes: {'a': 'true', 'left': 'true', 'right': 'exit 4'},
    );
    expect(code, 1);
    String short(Run run) => run.id.substring(0, 4);
    final a = short(await runAt(session, 'a'));
    final left = short(await runAt(session, 'left'));
    final right = short(await runAt(session, 'right'));
    final lines = const LineSplitter().convert(err);
    expect(lines, hasLength(12));
    const time = r'^\d\d:\d\d:\d\d ';
    expect(
      lines,
      containsAll([
        matches('$time$a run-started a\$'),
        matches('$time$a step-started a\$'),
        matches('$time$a step-finished a exit 0\$'),
        matches('$time$a run-split $left left, $right right\$'),
        matches('$time$left run-started left\$'),
        matches('$time$left run-finished\$'),
        matches('$time$right step-finished right exit 4\$'),
        matches('$time$right run-failed exited with code 4\$'),
      ]),
    );
  });

  group('Engine.stop', () {
    test('ends every running step and writes no more events', () async {
      final fake = FakeProgram(
        {
          'start': ['hang', 'wait'],
          'nodes': {
            'hang': {'command': 'hang', 'then': 'after'},
            'wait': {'command': 'wait'},
            'after': {'command': 'after'},
          },
        },
        nodes: {
          'hang': 'echo \$\$ > hang.pid\nwhile :; do sleep 0.05; done',
          'wait': 'echo \$\$ > wait.pid\nwhile :; do sleep 0.05; done',
          'after': 'true',
        },
      );
      final graph = (await GraphProgram([fake.path]).describe()).graph;
      final session = await FsStore(fake.runsDir).createSession(
        graphName: 'graph',
        graph: graph.json,
        startNodes: [
          (node: 'hang', takesInput: false),
          (node: 'wait', takesInput: false),
        ],
      );
      final progress = IOSink(Capture());
      final engine = Engine(
        store: session,
        graph: graph,
        program: GraphProgram([fake.path]),
        progress: progress,
      );
      final driving = engine.drive();
      final pids = [
        for (final node in ['hang', 'wait'])
          File(p.join(fake.dir, '$node.pid')),
      ];
      await waitFor(() => pids.every((pid) => pid.existsSync()));
      await engine.stop();
      await driving.timeout(const Duration(seconds: 5));
      for (final pid in pids) {
        final alive = Process.runSync('kill', [
          '-0',
          pid.readAsStringSync().trim(),
        ]);
        expect(alive.exitCode, isNot(0), reason: '${pid.path} still runs');
      }
      for (final node in ['hang', 'wait']) {
        expect(await journal(session, (await runAt(session, node)).id), [
          'run-started $node',
          'step-started $node',
        ]);
      }
      await progress.close();
    });
  });

  group('a session that cannot be stored', () {
    /// The line the engine ends with when it cannot store the session:
    /// what failed, on which path, and why.
    Matcher storeFailure(String path, String why) =>
        matches('^cannot store the session: \\w.* \\S*$path: $why\$');

    /// Gives back the write permission chmod took from [path], so that the
    /// test's directory can be deleted.
    void restoreWrite(String path) =>
        addTearDown(() => Process.runSync('chmod', ['-R', 'u+rwx', path]));

    /// Whether the process of the node script [node], which wrote its pid to
    /// `<node>.pid`, still runs.
    bool isRunning(FakeProgram fake, String node) {
      final pid = File(p.join(fake.dir, '$node.pid')).readAsStringSync();
      return Process.runSync('kill', ['-0', pid.trim()]).exitCode == 0;
    }

    /// A node script that writes its pid to `<node>.pid` and runs for 20 s,
    /// should the engine not stop it.
    const waitAndLoop =
        'echo \$\$ > "\$(basename "\$0" .sh).pid"\n'
        'i=0; while [ \$i -lt 400 ]; do sleep 0.05; i=\$((i + 1)); done';

    test('removed while steps run: every step stops, one line says why, '
        'exit 3', () async {
      final fake = FakeProgram(
        {
          'start': ['remove', 'wait'],
          'nodes': {
            'remove': {'command': 'remove'},
            'wait': {'command': 'wait'},
          },
        },
        nodes: {
          'remove': '${waitForFile('wait.pid')}\nrm -rf runs',
          'wait': waitAndLoop,
        },
      );
      final result = await nanoflow(['run', '--', fake.path])
          .timeout(const Duration(seconds: 15));

      expect(result.code, 3, reason: result.err);
      expect(result.out, matches(r'^[0-9a-f-]{36}\n$'));
      final lines = const LineSplitter().convert(result.err);
      expect(
        lines.last,
        storeFailure(r'/log\.jsonl', 'No such file or directory'),
      );
      expect(lines.where((line) => line.startsWith('cannot ')), hasLength(1));
      expect(isRunning(fake, 'wait'), isFalse);
      expect(Directory(fake.runsDir).existsSync(), isFalse);
    });

    test('a document it cannot write: no event after it, exit 3; once it '
        'can, --resume finishes the session', () async {
      final fake = FakeProgram(
        {
          'start': 'make',
          'nodes': {
            'make': {'command': 'make', 'out': object},
          },
        },
        nodes: {
          // Only the first time: the step that runs again on --resume
          // leaves the directory as it is.
          'make':
              '[ -e chmodded ] || { touch chmodded; '
              'chmod 500 runs/*/documents; }\n'
              "echo '{}'",
        },
      );
      restoreWrite(fake.runsDir);
      final result = await nanoflow(['run', '--', fake.path])
          .timeout(const Duration(seconds: 15));

      expect(result.code, 3, reason: result.err);
      final lines = const LineSplitter().convert(result.err);
      expect(lines.last, storeFailure(r'/documents/\S+', 'Permission denied'));
      final id = result.out.trim();
      final session = (await FsStore(fake.runsDir).openSession(id))!;
      final run = await onlyRun(session);
      expect(await journal(session, run.id), [
        'run-started make',
        'step-started make',
      ]);

      Process.runSync('chmod', ['-R', 'u+rwx', fake.runsDir]);
      final resumed = await nanoflow(['run', '--resume', id, '--', fake.path]);
      expect(resumed.code, 0, reason: resumed.err);
      expect(await journal(session, run.id), [
        'run-started make',
        'step-started make',
        'step-started make',
        'step-finished 0',
        'run-finished',
      ]);
    });

    test('in a run a split made: every step stops, exit 3', () async {
      final fake = FakeProgram(
        {
          'start': 'split',
          'nodes': {
            'split': {
              'command': 'split',
              'then': ['remove', 'wait'],
            },
            'remove': {'command': 'remove'},
            'wait': {'command': 'wait'},
          },
        },
        nodes: {
          'split': 'true',
          'remove': '${waitForFile('wait.pid')}\nrm -rf runs',
          'wait': waitAndLoop,
        },
      );
      final result = await nanoflow(['run', '--', fake.path])
          .timeout(const Duration(seconds: 15));

      expect(result.code, 3, reason: result.err);
      expect(
        const LineSplitter().convert(result.err).last,
        storeFailure(r'/log\.jsonl', 'No such file or directory'),
      );
      expect(isRunning(fake, 'wait'), isFalse);
    });

    test('a step log it cannot write, as on a full disk: every step stops, '
        'one line says why, exit 3', () async {
      final fake = FakeProgram(
        {
          'start': ['noisy', 'wait'],
          'nodes': {
            'noisy': {'command': 'noisy'},
            'wait': {'command': 'wait'},
          },
        },
        nodes: {
          // 8 KB to its log once wait runs, and then it keeps running: the
          // log fails while the step runs.
          'noisy':
              'echo \$\$ > noisy.pid\n'
              '${waitForFile('wait.pid')}\n'
              'i=0; while [ \$i -lt 40 ]; do '
              'printf "%0200d\\n" 0 >&2; i=\$((i + 1)); done\n'
              '$waitAndLoop',
          'wait': waitAndLoop,
        },
      );
      // No file may grow past 4 blocks of 512 bytes or more: the session's
      // own files fit, the noisy step's log does not. A write past it fails
      // with EFBIG instead of the signal killing the engine.
      final engine = await Process.start('/bin/sh', [
        '-c',
        r'''trap '' XFSZ; ulimit -f 4; exec "$0" "$@"''',
        Platform.resolvedExecutable,
        'bin/nanoflow.dart',
        'run',
        '--',
        fake.path,
      ]);
      addTearDown(() => engine.kill(ProcessSignal.sigkill));
      final out = engine.stdout.transform(utf8.decoder).join();
      final err = engine.stderr.transform(utf8.decoder).join();
      final code = await engine.exitCode.timeout(const Duration(seconds: 30));

      expect(code, 3, reason: await err);
      expect(await out, matches(r'^[0-9a-f-]{36}\n$'));
      final lines = const LineSplitter().convert(await err);
      expect(
        lines.last,
        storeFailure(r'/command\.log', 'File too large'),
        reason: await err,
      );
      expect(lines.where((line) => line.startsWith('cannot ')), hasLength(1));
      expect(isRunning(fake, 'noisy'), isFalse);
      expect(isRunning(fake, 'wait'), isFalse);
    });

    test('one that cannot be created: no session, one line says why, '
        'exit 2', () async {
      final fake = FakeProgram(
        {
          'start': 'a',
          'nodes': {
            'a': {'command': 'a'},
          },
        },
        nodes: {'a': 'true'},
      );
      Directory(fake.runsDir).createSync();
      Process.runSync('chmod', ['500', fake.runsDir]);
      restoreWrite(fake.runsDir);

      final result = await nanoflow(['run', '--', fake.path]);

      expect(result.code, 2);
      expect(result.out, isEmpty);
      expect(const LineSplitter().convert(result.err), [
        storeFailure(r'/runs/\.tmp-\S+', 'Permission denied'),
      ]);
    });

    test('--resume of one that cannot be opened: one line says why, '
        'exit 2', () async {
      final fake = FakeProgram(
        {
          'start': 'a',
          'nodes': {
            'a': {'command': 'a'},
          },
        },
        nodes: {'a': 'true'},
      );
      final ran = await nanoflow(['run', '--', fake.path]);
      expect(ran.code, 0, reason: ran.err);
      final sessionDir = Directory(fake.runsDir).listSync().single.path;
      Process.runSync('chmod', ['000', sessionDir]);
      restoreWrite(sessionDir);

      final result = await nanoflow([
        'run',
        '--resume',
        ran.out.trim(),
        '--',
        fake.path,
      ]);

      expect(result.code, 2);
      expect(result.out, isEmpty);
      expect(const LineSplitter().convert(result.err), [
        storeFailure(r'/\.engine\.lock', 'Permission denied'),
      ]);
    });
  });
}

/// A sink's bytes, like [Capture], and a call of [onData] for every chunk
/// written to it.
final class _OnData implements StreamConsumer<List<int>> {
  _OnData(this.onData);

  final void Function() onData;

  final _capture = Capture();

  String get text => _capture.text;

  @override
  Future<void> addStream(Stream<List<int>> stream) => _capture.addStream(
    stream.map((chunk) {
      onData();
      return chunk;
    }),
  );

  @override
  Future<void> close() => _capture.close();
}
