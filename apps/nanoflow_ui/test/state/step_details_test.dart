import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/session_feed.dart';
import 'package:nanoflow_ui/state/step_details.dart';

import 'support.dart';

void main() {
  group('the details of a step (ui-spec «Logs»)', () {
    test('name the step, its session, its place, and how it is', () {
      final j = Journal('a1b2-session', workflow: 'inPlace');
      final id = j.step('plan', 0, end: 3, output: 'doc-1', place: copiesAt(4));
      final details = stepDetails(j.data, id)!;
      expect(details.sessionId, 'a1b2-session');
      expect(details.stepId, id);
      expect(details.name, 'plan');
      expect(details.place, copiesAt(4));
      expect(details.status, StepStatus.finished);
      expect(details.running, isFalse);
      expect(details.error, isNull);
    });

    test("a finished step's output is the document step-finished names", () {
      final j = Journal('a1b2-session', workflow: 'inPlace');
      final id = j.step('plan', 0, end: 3, output: 'doc-1');
      final output = stepDetails(j.data, id)!.output;
      expect(output.state, DocumentState.present);
      expect(output.documentId, 'doc-1');
    });

    test('a running step has no output yet', () {
      final j = Journal('a1b2-session', workflow: 'inPlace');
      final id = j.step('plan', 0);
      final details = stepDetails(j.data, id)!;
      expect(details.running, isTrue);
      expect(details.output.state, DocumentState.notYet);
      expect(details.output.message, 'Not yet: the step is still running');
    });

    test('a failed step has no output: its error and stack instead', () {
      final j = Journal('a1b2-session', workflow: 'inPlace');
      final id = j.step('plan', 0, end: 2, failed: true);
      final details = stepDetails(j.data, id)!;
      expect(details.output.state, DocumentState.missing);
      expect(details.output.message, 'No output: the step failed');
      expect(details.error, 'StateError: plan failed');
      expect(details.stack, '#0 main');
    });

    test('a step that failed, then ran again and finished, has no error', () {
      final j = Journal('a1b2-session', workflow: 'inPlace');
      final id = j.step('plan', 0, end: 2, failed: true);
      j.events
        ..add(StepStarted(time: at(5), stepId: id))
        ..add(StepFinished(time: at(6), stepId: id, outputId: 'doc-2'));
      final details = stepDetails(j.data, id)!;
      expect(details.error, isNull);
      expect(details.output.documentId, 'doc-2');
    });

    test('none for a step whose record is not read yet: it has no name', () {
      final j = Journal('a1b2-session', workflow: 'inPlace');
      final id = j.step('plan', 0, place: copiesAt(4));
      expect(stepDetails(SessionData(j.session, events: j.events), id), isNull);
    });

    test('none for a step that has not started', () {
      final j = Journal('a1b2-session', workflow: 'inPlace');
      expect(stepDetails(j.data, 'nope'), isNull);
    });
  });
}
