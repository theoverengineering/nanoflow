import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/effect_details.dart';
import 'package:nanoflow_ui/state/session_feed.dart';
import 'package:nanoflow_ui/state/visits.dart' show StartOutcome;

import 'support.dart';

void main() {
  group('the details of an effect (ui-spec «Logs»)', () {
    test('name the effect, its session, its place, and how it is', () {
      final j = Journal('a1b2-session', workflow: 'inPlace');
      final id = j.effect(
        'plan',
        0,
        end: 3,
        output: 'doc-1',
        place: packagesAt(4),
      );
      final details = effectDetails(j.data, id)!;
      expect(details.sessionId, 'a1b2-session');
      expect(details.effectId, id);
      expect(details.name, 'plan');
      expect(details.place, packagesAt(4));
      expect(details.status, StartOutcome.finished);
      expect(details.running, isFalse);
      expect(details.error, isNull);
    });

    test(
      "a finished effect's output is the document effect-finished names",
      () {
        final j = Journal('a1b2-session', workflow: 'inPlace');
        final id = j.effect('plan', 0, end: 3, output: 'doc-1');
        final output = effectDetails(j.data, id)!.output;
        expect(output.state, DocumentState.present);
        expect(output.documentId, 'doc-1');
      },
    );

    test('a running effect has no output yet', () {
      final j = Journal('a1b2-session', workflow: 'inPlace');
      final id = j.effect('plan', 0);
      final details = effectDetails(j.data, id)!;
      expect(details.running, isTrue);
      expect(details.output.state, DocumentState.notYet);
      expect(details.output.message, 'Not yet: the effect is still running');
    });

    test('an effect that was running when the process of its session went '
        'is interrupted: no output yet (owner spec §6)', () {
      final j = Journal('a1b2-session', workflow: 'inPlace');
      final id = j.effect('plan', 0);
      j.processGone();
      final details = effectDetails(j.data, id)!;
      expect(details.status, StartOutcome.interrupted);
      expect(details.running, isFalse);
      expect(details.output.state, DocumentState.notYet);
      expect(
        details.output.message,
        'Not yet: the effect was interrupted — the process stopped',
      );
    });

    test('a failed effect has no output: its error and stack instead', () {
      final j = Journal('a1b2-session', workflow: 'inPlace');
      final id = j.effect('plan', 0, end: 2, failed: true);
      final details = effectDetails(j.data, id)!;
      expect(details.output.state, DocumentState.missing);
      expect(details.output.message, 'No output: the effect failed');
      expect(details.error, 'StateError: plan failed');
      expect(details.stack, '#0 main');
    });

    test(
      'an effect that failed, then ran again and finished, has no error',
      () {
        final j = Journal('a1b2-session', workflow: 'inPlace');
        final id = j.effect('plan', 0, end: 2, failed: true);
        j.events
          ..add(EffectStarted(time: at(5), effectId: id))
          ..add(EffectFinished(time: at(6), effectId: id, outputId: 'doc-2'));
        final details = effectDetails(j.data, id)!;
        expect(details.error, isNull);
        expect(details.output.documentId, 'doc-2');
      },
    );

    test('none for an effect whose record is not read yet: it has no name', () {
      final j = Journal('a1b2-session', workflow: 'inPlace');
      final id = j.effect('plan', 0, place: packagesAt(4));
      expect(
        effectDetails(SessionData(j.session, events: j.events), id),
        isNull,
      );
    });

    test('none for an effect that has not started', () {
      final j = Journal('a1b2-session', workflow: 'inPlace');
      expect(effectDetails(j.data, 'nope'), isNull);
    });
  });
}
