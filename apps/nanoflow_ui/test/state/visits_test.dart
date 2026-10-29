import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/effect_places.dart';
import 'package:nanoflow_ui/state/session_feed.dart';
import 'package:nanoflow_ui/state/visits.dart';

import 'support.dart';

void main() {
  final file = packagesGraphFile();
  final inPlace = file.functions['lib/packages.dart#inPlace']!;
  final places = EffectPlaces.of(inPlace, file.functions);
  final ship = file.functions['lib/packages.dart#ship']!;
  final upload = ship.body.node('1')! as EffectNode;

  /// A plan and two uploads of ship().
  Journal journal() => Journal('a1b2-session', workflow: 'inPlace')
    ..effect('plan', 0, end: 1, place: packagesAt(4))
    ..effect('upload', 1, end: 5, place: packagesAt(7))
    ..effect('upload', 2, end: 3, place: '/home/me/packages/${packagesAt(7)}');

  group('the visits of an effect (ui-spec «Окно деталей эффекта»)', () {
    test('are the effects on the nodes it is on, by their first '
        'effect-started', () {
      final j = journal();
      final session = j.data;
      final visits = visitsLike(
        session,
        session.state.effects,
        places,
        j.effects[1].id,
      );
      expect(visits.map((visit) => visit.effectId), [
        j.effects[1].id,
        j.effects[2].id,
      ]);
      expect(visits.first.name, 'upload');
    });

    test(
      'of an effect not on the graph: the effects at its very place, with its '
      'name',
      () {
        final j = Journal('a1b2-session', workflow: 'inPlace')
          ..effect('stray', 0, end: 1, place: 'lib/old.dart:3')
          ..effect('stray', 1, end: 2, place: 'lib/old.dart:3')
          ..effect('other', 2, end: 3, place: 'lib/old.dart:4')
          ..effect('loose', 3, end: 4)
          ..effect('loose', 4, end: 5)
          ..effect('free', 5, end: 6);
        final session = j.data;
        List<String> visits(int i) => [
          for (final visit in visitsLike(
            session,
            session.state.effects,
            places,
            j.effects[i].id,
          ))
            visit.effectId,
        ];
        expect(visits(0), [j.effects[0].id, j.effects[1].id]);
        expect(visits(3), [j.effects[3].id, j.effects[4].id]);
      },
    );

    test('an effect outside the effects shown is its own only visit', () {
      final j = journal();
      final session = j.data;
      expect(
        visitsLike(
          session,
          const [],
          places,
          j.effects[1].id,
        ).map((visit) => visit.effectId),
        [j.effects[1].id],
      );
    });

    test('of an effect on a node: the effects on that node', () {
      final j = journal();
      final session = j.data;
      expect(
        visitsTo(
          session,
          session.state.effects,
          places,
          upload,
        ).map((visit) => visit.effectId),
        [j.effects[1].id, j.effects[2].id],
      );
    });

    test('only among the effects shown', () {
      final j = journal();
      final session = j.data;
      expect(
        visitsTo(
          session,
          session.state.effects.take(2),
          places,
          upload,
        ).map((visit) => visit.effectId),
        [j.effects[1].id],
      );
    });

    test('a double click on a node opens its last effect', () {
      final j = journal();
      final session = j.data;
      expect(
        visitToOpen(session, session.state.effects, places, upload)!.effectId,
        j.effects[2].id,
      );
      expect(
        visitToOpen(
          session,
          session.state.effects,
          places,
          ship.body.node('3')! as EffectNode,
        ),
        isNull,
      );
    });
  });

  test('the starts of an effect: each with how it ended — finished, failed, '
      'interrupted by the next start, or running', () {
    final j = Journal('a1b2-session', workflow: 'inPlace');
    final id = j.effect('plan', 0, end: 2, failed: true, restarts: const []);
    j.events
      ..add(EffectStarted(time: at(5), effectId: id))
      ..add(EffectStarted(time: at(9), effectId: id))
      ..add(EffectFinished(time: at(10), effectId: id, outputId: 'doc'))
      ..add(EffectStarted(time: at(12), effectId: id));
    expect(startsOf(j.data, id), [
      (at: at(0), outcome: StartOutcome.failed),
      (at: at(5), outcome: StartOutcome.interrupted),
      (at: at(9), outcome: StartOutcome.finished),
      (at: at(12), outcome: StartOutcome.running),
    ]);
  });

  group('in a session whose process is gone (owner spec §6)', () {
    test('the last start of an effect that was running was interrupted', () {
      final j = Journal('a1b2-session', workflow: 'inPlace');
      final done = j.effect('plan', 0, end: 2);
      final id = j.effect('upload', 1, restarts: [3]);
      j.processGone();
      expect(startsOf(j.data, id), [
        (at: at(1), outcome: StartOutcome.interrupted),
        (at: at(3), outcome: StartOutcome.interrupted),
      ]);
      expect(startsOf(j.data, done), [
        (at: at(0), outcome: StartOutcome.finished),
      ]);
    });

    test('an effect stands as its last start: interrupted while it was '
        'running, else as its journal tells', () {
      final j = Journal('a1b2-session', workflow: 'inPlace')
        ..effect('plan', 0, end: 2)
        ..effect('upload', 1, end: 3, failed: true)
        ..effect('verify', 4);
      StartOutcome outcomeAt(SessionData session, int i) =>
          outcomeOf(session, session.state.effects[i]);

      final live = j.data;
      expect(
        [for (var i = 0; i < 3; i++) outcomeAt(live, i)],
        [StartOutcome.finished, StartOutcome.failed, StartOutcome.running],
      );
      j.processGone();
      final gone = j.data;
      expect(
        [for (var i = 0; i < 3; i++) outcomeAt(gone, i)],
        [StartOutcome.finished, StartOutcome.failed, StartOutcome.interrupted],
      );
      j.owned(testOwner, alive: null);
      expect(outcomeAt(j.data, 2), StartOutcome.running);
    });
  });
}
