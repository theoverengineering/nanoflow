import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/state/selection.dart';
import 'package:nanoflow_ui/state/session_feed.dart';

import 'support.dart';

/// A session [id] with one root run started at [startedAt].
SessionData _session(String id, num startedAt) => sessionOf([
  Journal('${id.substring(0, 4)}-run', node: 'collect', startedAt: startedAt)
    ..step('collect', startedAt),
], id: id);

void main() {
  late Selection selection;
  late int notified;

  setUp(() {
    selection = Selection();
    notified = 0;
    selection.addListener(() => notified++);
  });

  (bool, String?, String?, String?) selected() => (
    selection.currentGraph,
    selection.sessionId,
    selection.runId,
    selection.stepId,
  );

  group('on opening the graph', () {
    test('the newest session is selected', () {
      selection.update([
        _session('olde-session', -60),
        _session('newe-session', 0),
      ], loading: false);
      expect(selection.currentGraph, isFalse);
      expect(selection.sessionId, 'newe-session');
    });

    test('without sessions Current graph is selected', () {
      selection.update(const [], loading: false);
      expect(selected(), (true, null, null, null));
    });

    test(
      'while the feed still loads, the newest session so far is selected',
      () {
        selection.update([_session('olde-session', -60)], loading: true);
        expect(selection.sessionId, 'olde-session');
        selection.update([
          _session('olde-session', -60),
          _session('newe-session', 0),
        ], loading: true);
        expect(selection.sessionId, 'newe-session');
        expect(selection.runId, 'newe-run');
      },
    );

    test('a choice made while the feed loads is kept', () {
      final old = _session('olde-session', -60);
      selection.update([old], loading: true);
      selection.showCurrentGraph();
      selection.update([old, _session('newe-session', 0)], loading: true);
      expect(selection.currentGraph, isTrue);
    });
  });

  group('new data', () {
    test('does not reset the selection: a new session does not take it', () {
      final old = _session('olde-session', -60);
      selection.update([old], loading: false);
      selection.update([old, _session('newe-session', 0)], loading: false);
      expect(selection.sessionId, 'olde-session');

      final empty = Selection()..update(const [], loading: false);
      empty.update([old], loading: false);
      expect(empty.currentGraph, isTrue);
    });

    test('does not reset the selected run and step', () {
      final mockup = Mockup();
      selection.update([mockup.session], loading: false);
      selection.selectRun(mockup.session, 'c3d4-run');
      selection.selectStep(mockup.session, 'k7f2-fix-4');
      mockup.e5f6.step('notify', 700);
      selection.update([mockup.session], loading: false);
      expect(selection.runId, 'c3d4-run');
      expect(selection.stepId, 'k7f2-fix-4');
    });

    test(
      'gives a session opened before its runs came its run once they come',
      () {
        final early = sessionOf(const [], id: 'earl-session');
        selection.showSession(early);
        expect(selection.runId, isNull);
        selection.update([_session('earl-session', 0)], loading: false);
        expect(selection.runId, 'earl-run');
        expect(selection.stepId, 'earl-collect-0');
      },
    );

    test('that changes nothing selected is not announced', () {
      final session = _session('olde-session', 0);
      selection.update([session], loading: false);
      notified = 0;
      selection.update([session], loading: false);
      expect(notified, 0);
    });
  });

  group('opening a session', () {
    test('selects its first running run and the run\'s last step', () {
      final mockup = Mockup();
      selection.showSession(mockup.session);
      expect(selected(), (false, 'a1b2-session', 'e5f6-run', 'e5f6-notify-0'));
      expect(notified, 1);
    });

    test('without running runs selects the first failed run', () {
      final finished = Journal('fini-run', node: 'collect', startedAt: 0);
      finished.step('collect', 0, end: 1);
      finished.finish(1);
      final failed = Journal('fail-run', node: 'collect', startedAt: 2);
      failed.fail(
        failed.step('collect', 2, end: 3, exit: 1),
        3,
        'exited with code 1',
      );
      final later = Journal('late-run', node: 'collect', startedAt: 4);
      later.fail(
        later.step('collect', 4, end: 5, exit: 1),
        5,
        'exited with code 1',
      );
      selection.showSession(sessionOf([later, finished, failed]));
      expect(selection.runId, 'fail-run');
      expect(selection.stepId, 'fail-collect-0');
    });

    test('without running or failed runs selects the last run by time', () {
      final first = Journal('firs-run', node: 'collect', startedAt: 0);
      first.step('collect', 0, end: 1);
      first.finish(1);
      final last = Journal('last-run', node: 'collect', startedAt: 2);
      last.step('collect', 2, end: 3);
      last.finish(3);
      selection.showSession(sessionOf([last, first]));
      expect(selection.runId, 'last-run');
    });

    test('selects an inherited step when the run has none of its own yet', () {
      final parent = Journal('pare-run', node: 'verdict', startedAt: 0);
      parent.step('verdict', 0, end: 1);
      parent.split(1);
      final child = Journal(
        'chil-run',
        parent: 'pare-run',
        node: 'notify',
        startedAt: 1,
      );
      selection.showSession(sessionOf([parent, child]));
      expect(selection.runId, 'chil-run');
      expect(selection.stepId, 'pare-verdict-0');
    });

    test('Current graph selects no session, run or step', () {
      selection.showSession(Mockup().session);
      selection.showCurrentGraph();
      expect(selected(), (true, null, null, null));
    });

    test('a run chosen in the switcher gets its last step selected', () {
      final mockup = Mockup();
      selection.showSession(mockup.session);
      selection.selectRun(mockup.session, 'k7f2-run');
      expect(selection.runId, 'k7f2-run');
      expect(selection.stepId, 'k7f2-verdict-6');
    });
  });

  group('following (ui-spec «Logs»)', () {
    test('while the last step of a running run is selected, the new step is '
        'selected as it starts', () {
      final mockup = Mockup();
      selection.update([mockup.session], loading: false);
      expect(selection.stepId, 'e5f6-notify-0');
      expect(selection.following, isTrue);

      mockup.e5f6.step('notify', 700);
      selection.update([mockup.session], loading: false);
      expect(selection.stepId, 'e5f6-notify-1');
    });

    test('selecting another step stops following; selecting the last one '
        'again resumes it', () {
      final mockup = Mockup();
      selection.update([mockup.session], loading: false);
      selection.selectStep(mockup.session, 'k7f2-collect-0');
      expect(selection.following, isFalse);
      mockup.e5f6.step('notify', 700);
      selection.update([mockup.session], loading: false);
      expect(selection.stepId, 'k7f2-collect-0');

      selection.selectStep(mockup.session, 'e5f6-notify-1');
      expect(selection.following, isTrue);
      mockup.e5f6.step('notify', 710);
      selection.update([mockup.session], loading: false);
      expect(selection.stepId, 'e5f6-notify-2');
    });
  });

  group('clicking a node', () {
    test('selects its last step among the selected run\'s steps, inherited '
        'ones too', () {
      final mockup = Mockup();
      selection.showSession(mockup.session);
      selection.clickNode(mockup.session, 'inspect');
      expect(selection.stepId, 'k7f2-inspect-5');
      expect(selection.following, isFalse);
      selection.clickNode(mockup.session, 'notify');
      expect(selection.stepId, 'e5f6-notify-0');
      expect(selection.following, isTrue);
    });

    test('without steps of the run on it does nothing', () {
      final mockup = Mockup();
      selection.showSession(mockup.session);
      notified = 0;
      selection.clickNode(mockup.session, 'publish');
      selection.clickNode(mockup.session, 'discard');
      expect(selection.stepId, 'e5f6-notify-0');
      expect(notified, 0);
    });
  });
}
