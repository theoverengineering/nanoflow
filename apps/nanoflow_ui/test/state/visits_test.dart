import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/state/visits.dart';

import 'support.dart';

void main() {
  final mockup = Mockup();

  List<String> visits(String node, {List<Journal>? runs}) => [
    for (final visit in visitsTo(
      runs == null ? mockup.session : sessionOf(runs),
      node,
    ))
      visit.stepId,
  ];

  group('the visits to a node (ui-spec «Окно деталей шага»)', () {
    test('are its steps in the session, by their first step-started', () {
      expect(visits('inspect'), ['k7f2-inspect-2', 'k7f2-inspect-5']);
      expect(visits('notify'), ['e5f6-notify-0']);
      expect(visits('discard'), isEmpty);
    });

    test('go across runs by time, not by run', () {
      final root = Journal('root-run', node: 'collect', startedAt: 0)
        ..step('collect', 0, end: 1)
        ..split(1);
      final first =
          Journal('frst-run', parent: 'root-run', node: 'fix', startedAt: 1)
            ..step('fix', 20, end: 21)
            ..step('fix', 30);
      final second = Journal(
        'scnd-run',
        parent: 'root-run',
        node: 'fix',
        startedAt: 1,
      )..step('fix', 10, end: 11);
      expect(visits('fix', runs: [root, first, second]), [
        'scnd-fix-0',
        'frst-fix-0',
        'frst-fix-1',
      ]);
    });

    test('started at the same time go in the order the runs were made', () {
      final root = Journal('root-run', node: 'collect', startedAt: 0)
        ..step('collect', 0, end: 1)
        ..split(1);
      Journal child(String id) =>
          Journal(id, parent: 'root-run', node: 'fix', startedAt: 1)
            ..step('fix', 2);
      expect(
        visits('fix', runs: [root, child('bbbb-run'), child('aaaa-run')]),
        ['aaaa-fix-0', 'bbbb-fix-0'],
      );
    });

    test('a visit is its step in its own run', () {
      final visit = visitOf(mockup.session, 'k7f2-inspect-5')!;
      expect(
        (visit.stepId, visit.runId, visit.node),
        ('k7f2-inspect-5', 'k7f2-run', 'inspect'),
      );
      expect(visitOf(mockup.session, 'nope'), isNull);
    });
  });

  group('a double click opens', () {
    test('the node\'s last step among the selected run\'s steps', () {
      expect(
        visitToOpen(mockup.session, 'e5f6-run', 'inspect')?.stepId,
        'k7f2-inspect-5',
      );
      expect(
        visitToOpen(mockup.session, 'e5f6-run', 'notify')?.stepId,
        'e5f6-notify-0',
      );
    });

    test('else the node\'s latest visit in the session', () {
      expect(
        visitToOpen(mockup.session, 'e5f6-run', 'publish')?.stepId,
        'c3d4-publish-0',
      );
      expect(
        visitToOpen(mockup.session, null, 'inspect')?.stepId,
        'k7f2-inspect-5',
      );
    });

    test('nothing for a node without visits', () {
      expect(visitToOpen(mockup.session, 'e5f6-run', 'discard'), isNull);
    });
  });

  group('the input of a step came from', () {
    InputSource? sourceOf(String stepId, {List<Journal>? runs}) {
      final session = runs == null ? mockup.session : sessionOf(runs);
      return inputSource(session, visitOf(session, stepId)!);
    }

    String? fromStep(String stepId, {List<Journal>? runs}) =>
        switch (sourceOf(stepId, runs: runs)) {
          FromStep(:final visit) => visit.stepId,
          _ => null,
        };

    test('the step whose output it is', () {
      expect(fromStep('k7f2-inspect-5'), 'k7f2-fix-4');
      expect(fromStep('k7f2-fix-4'), 'k7f2-inspect-2');
      final from = sourceOf('k7f2-inspect-5')! as FromStep;
      expect((from.visit.node, from.time), ('fix', '14:08:54'));
    });

    test('through a fork, which passes it on unchanged', () {
      expect(fromStep('k7f2-inspect-2'), 'k7f2-collect-0');
      expect(fromStep('k7f2-is-empty-1'), 'k7f2-collect-0');
    });

    test('into a run a split made, from its parent\'s step', () {
      expect(fromStep('e5f6-notify-0'), 'k7f2-inspect-5');
      expect(fromStep('c3d4-publish-0'), 'k7f2-inspect-5');
    });

    test('the launch, for the first step of a root run', () {
      expect(sourceOf('k7f2-collect-0'), isA<LaunchInput>());
    });

    test('the launch, through a fork at the start', () {
      final run = Journal('fork-run', node: 'is-empty', startedAt: 0)
        ..step('is-empty', 0, end: 1, input: 'request', output: 'no')
        ..step('inspect', 1, input: 'request');
      expect(sourceOf('fork-inspect-1', runs: [run]), isA<LaunchInput>());
    });

    test('nowhere for a step without input', () {
      final run = Journal('none-run', node: 'collect', startedAt: 0)
        ..step('collect', 0, end: 1, output: 'change');
      expect(sourceOf('none-collect-0', runs: [run]), isNull);
    });
  });

  test('the starts of a step: all but the last were interrupted', () {
    final run = mockup.session.runs['k7f2-run']!;
    expect(startsOf(run, 'k7f2-inspect-5'), [
      (at: at(369), interrupted: true),
      (at: at(400), interrupted: false),
    ]);
    expect(startsOf(run, 'k7f2-fix-4'), [(at: at(343), interrupted: false)]);
  });
}
