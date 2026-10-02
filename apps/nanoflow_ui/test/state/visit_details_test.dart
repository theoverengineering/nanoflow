import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/session_feed.dart';
import 'package:nanoflow_ui/state/step_details.dart';
import 'package:nanoflow_ui/state/visit_details.dart';
import 'package:nanoflow_ui/state/visits.dart';

import 'support.dart';

void main() {
  final mockup = Mockup();

  VisitDetails details(
    String node, {
    String? stepId,
    SessionData? session,
    DateTime? now,
  }) {
    final shown = session ?? mockup.session;
    return visitDetails(
      session: shown,
      graph: shown.graph,
      node: node,
      stepId: stepId,
      now: now ?? Mockup.now,
    );
  }

  group('the step details window (ui-spec «Окно деталей шага»)', () {
    test('shows a visit among all the visits to its node', () {
      final second = details('inspect', stepId: 'k7f2-inspect-5');
      expect(second.visit?.stepId, 'k7f2-inspect-5');
      expect(second.visitText, 'Visit 2 of 2');
      expect(second.previous?.stepId, 'k7f2-inspect-2');
      expect(second.next, isNull);
      expect(second.visit?.runId, 'k7f2-run');

      final first = details('inspect', stepId: 'k7f2-inspect-2');
      expect(first.visitText, 'Visit 1 of 2');
      expect((first.previous, first.next?.stepId), (null, 'k7f2-inspect-5'));
    });

    test('of a finished step: its exit code and how long it took', () {
      final inspect = details('inspect', stepId: 'k7f2-inspect-5');
      expect(inspect.result?.status, StepStatus.finished);
      expect(inspect.result?.text, 'exit 0 · 4m 02s');
      final facts = inspect.facts!;
      expect(facts.started, '14:09:20.000');
      expect(facts.finished, '14:13:22.000');
      expect(facts.took, 'took 4m 02s');
      expect(facts.exitCode, 0);
      expect(facts.starts, [
        (time: '14:09:20', interrupted: true),
        (time: '14:09:51', interrupted: false),
      ]);
    });

    test('of a running step: the time it has been running, nothing more', () {
      final notify = details('notify', stepId: 'e5f6-notify-0');
      expect(notify.result?.status, StepStatus.running);
      expect(notify.result?.text, 'running · 2m 14s');
      expect(
        details('notify', stepId: 'e5f6-notify-0', now: at(747)).result?.text,
        'running · 2m 15s',
      );
      expect(notify.facts!.finished, isNull);
      expect(notify.facts!.took, isNull);
      expect(notify.facts!.exitCode, isNull);
      expect(notify.step?.output.state, DocumentState.undeclared);
      expect(notify.error, isNull);
    });

    test('of a failed step: its exit code and the run\'s error', () {
      final run = Journal('fail-run', node: 'collect', startedAt: 0);
      run.fail(
        run.step('collect', 0, end: 28, exit: 1, input: 'request'),
        28,
        'exited with code 1',
      );
      final collect = details(
        'collect',
        stepId: 'fail-collect-0',
        session: sessionOf([run]),
      );
      expect(collect.result?.status, StepStatus.failed);
      expect(collect.result?.text, 'exit 1 · 28s');
      expect(collect.error, 'exited with code 1');
      expect(collect.facts!.exitCode, 1);
    });

    test('of a step that could not start: failed, without a code', () {
      final run = Journal('gone-run', node: 'collect', startedAt: 0);
      run.fail(
        run.step('collect', 0, input: 'request'),
        0.1,
        'cannot start the graph program: no such file',
      );
      final collect = details(
        'collect',
        stepId: 'gone-collect-0',
        session: sessionOf([run]),
      );
      expect(collect.result?.text, 'failed · 0.1s');
      expect(collect.facts!.finished, isNull);
      expect(collect.facts!.exitCode, isNull);
    });

    test('where the input came from', () {
      final inspect = details('inspect', stepId: 'k7f2-inspect-5');
      expect((inspect.source! as FromStep).visit.stepId, 'k7f2-fix-4');
      expect(inspect.step?.input.documentId, 'change-2');
      expect(
        details('collect', stepId: 'k7f2-collect-0').source,
        isA<LaunchInput>(),
      );
    });

    test('a fork\'s output is its outcome', () {
      final verdict = details('verdict', stepId: 'k7f2-verdict-6');
      expect(verdict.step?.output.documentId, 'verdict-outcome-2');
      expect(verdict.description!.fork, isTrue);
    });

    test('a node without visits: its description alone', () {
      final discard = details('discard');
      expect(discard.visit, isNull);
      expect(discard.visits, isEmpty);
      expect(discard.visitText, isNull);
      expect(
        (discard.step, discard.result, discard.facts, discard.source),
        (null, null, null, null),
      );
      expect(discard.description!.run, 'nodes/discard/run.sh');
    });

    test('a step that is not a visit to the node is not shown', () {
      final inspect = details('inspect', stepId: 'k7f2-fix-4');
      expect(inspect.visit, isNull);
      expect(inspect.visits, hasLength(2));
    });

    test('a node of the current graph, without a session', () {
      final described = visitDetails(
        session: null,
        graph: Graph.fromJson(reviewGraph),
        node: 'inspect',
        stepId: null,
        now: Mockup.now,
      );
      expect(described.visits, isEmpty);
      expect(described.description!.run, 'nodes/inspect/run.sh');
    });
  });

  group('the node\'s description', () {
    NodeDescription describe(String node) => details(node).description!;

    /// The ways as `accepted → publish, notify`; `→` alone when the run ends.
    List<String> waysOf(NodeDescription node) => [
      for (final way in node.ways)
        '${way.outcome ?? ''} → '
                '${way.targets.map((target) => target.name).join(', ')}'
            .trim(),
    ];

    test('of a worker: its command, its in and out, where it goes', () {
      final inspect = describe('inspect');
      expect(inspect.fork, isFalse);
      expect(inspect.runTitle, 'Command');
      expect(inspect.run, 'nodes/inspect/run.sh');
      expect(
        (inspect.input?.label, inspect.input?.fields),
        ('#/Change', '{ id, path }'),
      );
      expect(
        (inspect.output?.label, inspect.output?.fields),
        ('#/Report', '{ change, findings[] }'),
      );
      expect(waysOf(inspect), ['→ verdict']);
      expect(inspect.ways.single.targets.single.fork, isTrue);
      expect(describe('fix').ways.single.targets.single.fork, isFalse);
    });

    test('of a worker without then or out: the run ends there', () {
      final notify = describe('notify');
      expect(notify.output, isNull);
      expect(waysOf(notify), ['→']);
    });

    test('of a fork: what it decides with, its outcomes and their '
        'targets', () {
      final verdict = describe('verdict');
      expect(verdict.fork, isTrue);
      expect(verdict.runTitle, 'Decide');
      expect(verdict.run, 'nodes/verdict/run.sh');
      expect(verdict.output, isNull);
      expect(waysOf(verdict), ['accepted → publish, notify', 'returned → fix']);
      expect(waysOf(describe('is-empty')), [
        'true → discard',
        'else → inspect',
      ]);
    });

    test('of a fork whose else leads nowhere', () {
      final run = Journal('else-run', node: 'pick', startedAt: null);
      final session = sessionOf(
        [run],
        graph: const {
          'start': 'pick',
          'nodes': {
            'pick': {
              'decide': 'pick.sh',
              'then': {'a': 'pick'},
              'else': <String>[],
            },
          },
        },
      );
      final pick = details('pick', session: session).description!;
      expect(pick.input, isNull);
      expect(waysOf(pick), ['a → pick', 'else →']);
    });

    test('of a node the graph does not have: none', () {
      expect(details('nope').description, isNull);
    });
  });
}
