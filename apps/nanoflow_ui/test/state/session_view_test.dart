import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/state/session_view.dart';

import 'support.dart';

void main() {
  final mockup = Mockup();
  final now = Mockup.now;
  final noOutcomes = outcomesOf(const {});

  group('the whole view', () {
    test('puts together what the session shows', () {
      final view = SessionView.of(
        mockup.session,
        now: now,
        outcomes: mockup.outcomes,
        runId: 'e5f6-run',
        stepId: 'k7f2-fix-4',
      );
      expect(view.summary!.statusText, 'Running for 12m 26s');
      expect(view.graph!.nodes.keys, contains('notify'));
      expect(view.runs, hasLength(3));
      expect(view.marks.stateOf('notify'), NodeState.running);
      expect(
        view.run!.header.text,
        'run e5f6 · 8 steps, 7 inherited from k7f2',
      );
      expect(view.run!.rows, hasLength(9));
      expect(view.run!.path.inputs, contains('notify'));
      expect(view.selectedNode, 'fix');
      expect(view.step!.stepId, 'k7f2-fix-4');
      expect(view.run!.scale.axis, ['0m', '6m', '12m']);
    });

    test('without a selected run shows no logs', () {
      final view = SessionView.of(
        mockup.session,
        now: now,
        outcomes: noOutcomes,
      );
      expect(view.run, isNull);
      expect(view.selectedNode, isNull);
      expect(view.step, isNull);
    });

    test('cannot be changed by the widgets that draw it', () {
      final view = SessionView.of(
        mockup.session,
        now: now,
        outcomes: mockup.outcomes,
        runId: 'e5f6-run',
      );
      final run = view.run!;
      expect(() => view.runs.clear(), throwsUnsupportedError);
      expect(() => run.rows.clear(), throwsUnsupportedError);
      expect(() => run.steps.clear(), throwsUnsupportedError);
      expect(() => run.path.exits.clear(), throwsUnsupportedError);
      expect(() => run.path.arrows.clear(), throwsUnsupportedError);
      expect(() => run.path.inputs.clear(), throwsUnsupportedError);
      expect(
        () => view.marks.markersOn('notify').clear(),
        throwsUnsupportedError,
      );
      expect(() => view.marks.passes.clear(), throwsUnsupportedError);
    });
  });
}
