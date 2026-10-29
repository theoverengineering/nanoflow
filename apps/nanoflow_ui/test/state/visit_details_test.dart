import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/effect_places.dart';
import 'package:nanoflow_ui/state/visit_details.dart';
import 'package:nanoflow_ui/state/visits.dart';

import 'support.dart';

void main() {
  final file = packagesGraphFile();
  final inPlace = file.functions['lib/packages.dart#inPlace']!;
  final places = EffectPlaces.of(inPlace, file.functions);
  final ship = file.functions['lib/packages.dart#ship']!;
  final now = at(746);

  /// Three runs' verify of ship(): finished in 4m 02s, running, failed in
  /// 0.1s.
  Journal journal() {
    final j = Journal('a1b2-session', workflow: 'inPlace');
    j.effect(
      'verify',
      9.118,
      end: 251.524,
      place: packagesAt(8),
      output: 'doc',
    );
    j.effect('verify', 612, place: packagesAt(8));
    j.effect('verify', 700, end: 700.1, failed: true, place: packagesAt(8));
    return j;
  }

  VisitDetails detailsOf(Journal j, int i) {
    final session = j.data;
    return visitDetails(
      session: session,
      effects: session.state.effects,
      places: places,
      effectId: j.effects[i].id,
      now: now,
    );
  }

  group('the effect details window (ui-spec «Окно деталей эффекта»)', () {
    test('shows a visit among all the visits to its node', () {
      final details = detailsOf(journal(), 1);
      expect(details.visitText, 'Visit 2 of 3');
      expect(details.previous!.effectId, details.visits[0].effectId);
      expect(details.next!.effectId, details.visits[2].effectId);
      expect(details.name, 'verify');
      expect(details.place, packagesAt(8));
    });

    test('of a finished effect: how long it took, when it started and '
        'finished', () {
      final details = detailsOf(journal(), 0);
      expect(details.result!.text, 'finished · 4m 02s');
      expect(details.result!.status, StartOutcome.finished);
      final facts = details.facts!;
      expect(facts.started, '14:03:20.118');
      expect(facts.finished, '14:07:22.524');
      expect(facts.took, 'took 4m 02s');
      expect(details.effect!.output.documentId, 'doc');
    });

    test('of a running effect: the time it has been running, nothing more', () {
      final details = detailsOf(journal(), 1);
      expect(details.result!.text, 'running · 2m 14s');
      expect(details.facts!.finished, isNull);
      expect(details.facts!.took, isNull);
    });

    test('of an effect that was running when the process of its session went: '
        'interrupted, how long it ran not known (owner spec §6)', () {
      // Killed in the middle of verify 3: the start of the effect is the
      // last event of the journal.
      final killed = Journal('a1b2-session', workflow: 'inPlace')
        ..effect('verify', 9.118, end: 251.524, place: packagesAt(8))
        ..effect('verify', 612, place: packagesAt(8));
      for (final (j, time) in [
        (journal()..processGone(), now),
        (journal()..processGone(), at(2000)),
        (killed..processGone(), now),
      ]) {
        final session = j.data;
        final details = visitDetails(
          session: session,
          effects: session.state.effects,
          places: places,
          effectId: j.effects[1].id,
          now: time,
        );
        expect(details.result!.status, StartOutcome.interrupted);
        expect(details.result!.text, 'interrupted');
        expect(details.facts!.finished, isNull);
        expect(details.facts!.took, isNull);
        expect(details.facts!.starts, [
          (time: '14:13:23', outcome: StartOutcome.interrupted),
        ]);
        expect(details.effect!.running, isFalse);
      }
    });

    test('of a failed effect: its error and stack', () {
      final details = detailsOf(journal(), 2);
      expect(details.result!.text, 'failed · 0.1s');
      expect(details.effect!.error, 'StateError: verify failed');
      expect(details.effect!.stack, '#0 main');
    });

    test('its starts, and how each ended', () {
      final j = journal();
      j.events.add(EffectStarted(time: at(800), effectId: j.effects[2].id));
      final starts = detailsOf(j, 2).facts!.starts;
      expect(starts, [
        (time: '14:14:51', outcome: StartOutcome.failed),
        (time: '14:16:31', outcome: StartOutcome.running),
      ]);
    });

    test('a node without effects: its name and place alone', () {
      final session = journal().data;
      final details = visitDetails(
        session: session,
        effects: session.state.effects,
        places: places,
        effectId: null,
        node: ship.body.node('3')! as EffectNode,
        now: now,
      );
      expect(details.name, 'tag');
      expect(details.place, packagesAt(9));
      expect(details.visits, isEmpty);
      expect(details.visitText, isNull);
      expect(details.effect, isNull);
      expect(details.result, isNull);
    });

    test('the doc of the effect\'s node, with a session and without', () {
      final json = packagesGraphFile().toJson();
      void document(Object? value) {
        if (value is Map) {
          if (value['kind'] == 'effect') {
            value['doc'] = 'Does ${value['name']}.';
          }
          value.values.forEach(document);
        } else if (value is List) {
          value.forEach(document);
        }
      }

      document(json['functions']);
      final documented = GraphFile.fromJson(json);
      final workflow = documented.functions['lib/packages.dart#inPlace']!;
      final shipped = documented.functions['lib/packages.dart#ship']!;
      final places = EffectPlaces.of(workflow, documented.functions);
      final j = journal();
      final details = visitDetails(
        session: j.data,
        effects: j.data.state.effects,
        places: places,
        effectId: j.effects[1].id,
        now: now,
      );
      expect(details.doc, 'Does verify.');
      final alone = visitDetails(
        session: null,
        effects: const [],
        places: places,
        effectId: null,
        node: shipped.body.node('1')! as EffectNode,
        now: now,
      );
      expect(alone.doc, 'Does upload.');
      expect(detailsOf(journal(), 1).doc, isNull);
    });

    test('a node of the current graph, without a session', () {
      final details = visitDetails(
        session: null,
        effects: const [],
        places: places,
        effectId: null,
        node: ship.body.node('1')! as EffectNode,
        now: now,
      );
      expect(details.name, 'upload');
      expect(details.visit, isNull);
    });
  });
}
