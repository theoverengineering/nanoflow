import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/session_feed.dart';
import 'package:nanoflow_ui/state/step_details.dart';

import 'support.dart';

void main() {
  final mockup = Mockup();

  StepDetails details(String runId, String stepId, {List<Journal>? runs}) =>
      stepDetails(
        runs == null ? mockup.session : sessionOf(runs),
        runId,
        stepId,
      )!;

  group('the details of a step (ui-spec «Logs»)', () {
    test('name the step, its run and session, and how it is', () {
      final notify = details('e5f6-run', 'e5f6-notify-0');
      expect(
        (notify.sessionId, notify.runId, notify.stepId, notify.node),
        ('a1b2-session', 'e5f6-run', 'e5f6-notify-0', 'notify'),
      );
      expect(notify.status, StepStatus.running);
      expect(notify.running, isTrue);
      expect(details('e5f6-run', 'k7f2-collect-0').running, isFalse);
    });

    test('an inherited step is its own run\'s', () {
      final collect = details('e5f6-run', 'k7f2-collect-0');
      expect(collect.runId, 'k7f2-run');
    });

    test('a step\'s input and output are its documents', () {
      final collect = details('k7f2-run', 'k7f2-collect-0');
      expect(collect.input.state, DocumentState.present);
      expect(collect.input.documentId, 'request');
      expect(collect.input.message, isNull);
      expect(collect.output.state, DocumentState.present);
      expect(collect.output.documentId, 'change-1');
    });

    test('a fork\'s output is its outcome', () {
      final verdict = details('k7f2-run', 'k7f2-verdict-6');
      expect(verdict.input.documentId, 'report-2');
      expect(verdict.output.documentId, 'verdict-outcome-2');
      expect(verdict.output.marked, isFalse);
    });

    test('a node that declares no out is marked —', () {
      final notify = details('e5f6-run', 'e5f6-notify-0');
      expect(notify.input.marked, isFalse);
      expect(notify.output.marked, isTrue);
      expect(notify.output.state, DocumentState.undeclared);
      expect(notify.output.message, 'This node declares no output');
    });

    test('a node that declares no in is marked —', () {
      const graph = <String, Object?>{
        'start': 'tick',
        'nodes': {
          'tick': {'command': 'date', 'out': <String, Object?>{}},
        },
      };
      final run = Journal('tick-run', node: 'tick', startedAt: 0)
        ..step('tick', 0, end: 1, output: 'time');
      final tick = stepDetails(
        sessionOf([run], graph: graph),
        'tick-run',
        'tick-tick-0',
      )!;
      expect(tick.input.marked, isTrue);
      expect(tick.input.message, 'This node declares no input');
      expect(tick.output.documentId, 'time');
    });

    test('a running step has no output yet', () {
      final run = Journal('runs-run', node: 'collect', startedAt: 0)
        ..step('collect', 0, end: 1, input: 'request', output: 'change')
        ..step('inspect', 1, input: 'change');
      final inspect = details('runs-run', 'runs-inspect-1', runs: [run]);
      expect(inspect.output.state, DocumentState.notYet);
      expect(inspect.output.marked, isFalse);
      expect(inspect.output.message, 'Not yet: the step is still running');
    });

    test('a failed step has no output', () {
      final run = Journal('fail-run', node: 'collect', startedAt: 0);
      run.fail(
        run.step('collect', 0, end: 1, exit: 1, input: 'request'),
        1,
        'exited with code 1',
      );
      final collect = details('fail-run', 'fail-collect-0', runs: [run]);
      expect(collect.status, StepStatus.failed);
      expect(collect.output.state, DocumentState.missing);
      expect(collect.output.message, 'No output: the step failed');
    });

    test('the output is the one step-finished names, before step.json says '
        'it', () {
      final run = Journal('done-run', node: 'collect', startedAt: 0)
        ..step('collect', 0, end: 1, input: 'request', output: 'change');
      final data = sessionOf([run]);
      final given = data.runs['done-run']!;
      final early = RunData(
        given.run,
        events: given.events,
        steps: [
          for (final step in given.steps.values)
            Step(
              id: step.id,
              runId: step.runId,
              inputId: step.inputId,
              outputId: null,
              log: step.log,
            ),
        ],
      );
      final session = SessionData(data.session, runs: [early]);
      expect(
        stepDetails(session, 'done-run', 'done-collect-0')!.output.documentId,
        'change',
      );
    });

    test('a step whose step.json is not read yet has no input yet', () {
      final run = Journal('soon-run', node: 'collect', startedAt: 0)
        ..step('collect', 0, input: 'request');
      final data = sessionOf([run]);
      final given = data.runs['soon-run']!;
      final session = SessionData(
        data.session,
        runs: [RunData(given.run, events: given.events)],
      );
      final collect = stepDetails(session, 'soon-run', 'soon-collect-0')!;
      expect(collect.input.state, DocumentState.notYet);
      expect(collect.input.message, 'Not read yet');
    });

    test('a step of a graph that cannot be read shows what it has', () {
      final run = Journal('oddg-run', node: 'collect', startedAt: 0)
        ..step('collect', 0, end: 1, output: 'change');
      final collect = stepDetails(
        sessionOf([run], graph: const {'nodes': 1}),
        'oddg-run',
        'oddg-collect-0',
      )!;
      expect(collect.input.marked, isFalse);
      expect(collect.input.state, DocumentState.missing);
      expect(collect.input.message, 'The step had no input');
      expect(collect.output.documentId, 'change');
    });

    test('none for a step the run does not show', () {
      expect(stepDetails(mockup.session, 'c3d4-run', 'e5f6-notify-0'), isNull);
      expect(stepDetails(mockup.session, 'nope-run', 'e5f6-notify-0'), isNull);
    });
  });
}
