import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/step_places.dart';
import 'package:nanoflow_ui/state/visits.dart';

import 'support.dart';

void main() {
  final file = copiesGraphFile();
  final inPlace = file.functions['lib/copies.dart#inPlace']!;
  final places = StepPlaces.of(inPlace, file.functions);
  final copies = inPlace.body.node('2')! as CopiesNode;
  final upload = copies.body.node('1')! as StepNode;

  /// Two copies' uploads and a plan.
  Journal journal() => Journal('a1b2-session', workflow: 'inPlace')
    ..step('plan', 0, end: 1, place: copiesAt(4))
    ..step('upload', 1, end: 5, place: copiesAt(7))
    ..step('upload', 2, end: 3, place: '/home/me/copies/${copiesAt(7)}');

  group('the visits of a step (ui-spec «Окно деталей шага»)', () {
    test('are the steps on the nodes it is on, by their first '
        'step-started', () {
      final j = journal();
      final session = j.data;
      final visits = visitsLike(
        session,
        session.state.steps,
        places,
        j.steps[1].id,
      );
      expect(visits.map((visit) => visit.stepId), [
        j.steps[1].id,
        j.steps[2].id,
      ]);
      expect(visits.first.name, 'upload');
    });

    test('of a step not on the graph: the steps at its very place, with its '
        'name', () {
      final j = Journal('a1b2-session', workflow: 'inPlace')
        ..step('stray', 0, end: 1, place: 'lib/old.dart:3')
        ..step('stray', 1, end: 2, place: 'lib/old.dart:3')
        ..step('other', 2, end: 3, place: 'lib/old.dart:4')
        ..step('loose', 3, end: 4)
        ..step('loose', 4, end: 5)
        ..step('free', 5, end: 6);
      final session = j.data;
      List<String> visits(int i) => [
        for (final visit in visitsLike(
          session,
          session.state.steps,
          places,
          j.steps[i].id,
        ))
          visit.stepId,
      ];
      expect(visits(0), [j.steps[0].id, j.steps[1].id]);
      expect(visits(3), [j.steps[3].id, j.steps[4].id]);
    });

    test('a step outside the steps shown is its own only visit', () {
      final j = journal();
      final session = j.data;
      expect(
        visitsLike(
          session,
          const [],
          places,
          j.steps[1].id,
        ).map((visit) => visit.stepId),
        [j.steps[1].id],
      );
    });

    test('of a step on a node: the steps on that node', () {
      final j = journal();
      final session = j.data;
      expect(
        visitsTo(
          session,
          session.state.steps,
          places,
          upload,
        ).map((visit) => visit.stepId),
        [j.steps[1].id, j.steps[2].id],
      );
    });

    test('only among the steps shown', () {
      final j = journal();
      final session = j.data;
      expect(
        visitsTo(
          session,
          session.state.steps.take(2),
          places,
          upload,
        ).map((visit) => visit.stepId),
        [j.steps[1].id],
      );
    });

    test('a double click on a node opens its last step', () {
      final j = journal();
      final session = j.data;
      expect(
        visitToOpen(session, session.state.steps, places, upload)!.stepId,
        j.steps[2].id,
      );
      expect(
        visitToOpen(
          session,
          session.state.steps,
          places,
          copies.body.node('3')! as StepNode,
        ),
        isNull,
      );
    });
  });

  test('the starts of a step: each with how it ended — finished, failed, '
      'interrupted by the next start, or running', () {
    final j = Journal('a1b2-session', workflow: 'inPlace');
    final id = j.step('plan', 0, end: 2, failed: true, restarts: const []);
    j.events
      ..add(StepStarted(time: at(5), stepId: id))
      ..add(StepStarted(time: at(9), stepId: id))
      ..add(StepFinished(time: at(10), stepId: id, outputId: 'doc'))
      ..add(StepStarted(time: at(12), stepId: id));
    expect(startsOf(j.data, id), [
      (at: at(0), outcome: StartOutcome.failed),
      (at: at(5), outcome: StartOutcome.interrupted),
      (at: at(9), outcome: StartOutcome.finished),
      (at: at(12), outcome: StartOutcome.running),
    ]);
  });
}
