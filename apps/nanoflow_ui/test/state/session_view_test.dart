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
    });

    test('without a selected run shows no logs', () {
      final view = SessionView.of(
        mockup.session,
        now: now,
        outcomes: noOutcomes,
      );
      expect(view.run, isNull);
      expect(view.selectedNode, isNull);
    });
  });
}
