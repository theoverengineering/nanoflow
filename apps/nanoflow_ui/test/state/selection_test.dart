import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/selection.dart';
import 'package:nanoflow_ui/state/session_feed.dart';

import 'support.dart';

/// A session [id] started at [startedAt] with one step running.
SessionData _session(String id, num startedAt) =>
    (Journal(id, startedAt: startedAt)..step('collect', startedAt)).data;

void main() {
  late DateTime clock;
  late Selection selection;
  late int notified;

  setUp(() {
    // The graph is opened at 14:20.
    clock = at(1009);
    selection = Selection(now: () => clock);
    notified = 0;
    selection.addListener(() => notified++);
  });

  (bool, String?, String?) selected() =>
      (selection.currentGraph, selection.sessionId, selection.stepId);

  /// Session a1b2: collect and inspect finished, notify running.
  Journal a1b2() => Journal('a1b2-session')
    ..step('collect', 1, end: 149)
    ..step('inspect', 150, end: 342)
    ..step('notify', 343);

  group('on opening the graph', () {
    test('the newest session started before then is selected, on its last '
        'step', () {
      selection.update([
        _session('olde-session', -60),
        _session('newe-session', 0),
      ]);
      expect(selected(), (false, 'newe-session', 'newe-collect-0'));
    });

    test('without such a session Current graph is selected', () {
      selection.update(const []);
      expect(selected(), (true, null, null));
    });

    test('sessions read in any order lead to the same choice', () {
      final old = _session('olde-session', -60);
      final newer = _session('newe-session', 0);
      selection.update([newer]);
      selection.update([newer, old]);
      expect(selection.sessionId, 'newe-session');

      final other = Selection(now: () => clock)..update([old]);
      expect(other.sessionId, 'olde-session');
      other.update([old, newer]);
      expect(other.sessionId, 'newe-session');
    });

    test('a session started after the graph was opened never takes the '
        'selection', () {
      final old = _session('olde-session', -60);
      selection.update([old]);
      clock = at(3000);
      selection.update([old, _session('newe-session', 2000)]);
      expect(selection.sessionId, 'olde-session');

      final empty = Selection(now: () => at(1009))..update(const []);
      empty.update([_session('newe-session', 2000)]);
      expect(empty.currentGraph, isTrue);
    });

    test('a choice the user made is kept', () {
      selection.showCurrentGraph();
      selection.update([_session('olde-session', -60)]);
      expect(selection.currentGraph, isTrue);
    });
  });

  group('opening again, for another workflow', () {
    test('forgets the choice and selects the newest session started before '
        'then', () {
      final old = _session('olde-session', -60);
      selection.showCurrentGraph();
      clock = at(3000);
      selection.reopen();
      expect(selected(), (true, null, null));
      selection.update([old, _session('newe-session', 2000)]);
      expect(selected(), (false, 'newe-session', 'newe-collect-0'));
    });
  });

  group('new data', () {
    test('does not reset the selected step', () {
      final session = a1b2();
      selection.update([session.data]);
      selection.selectStep(session.data, 'a1b2-collect-0');
      session.step('publish', 400);
      selection.update([session.data]);
      expect(selection.stepId, 'a1b2-collect-0');
    });

    test('gives a session opened before its steps came its last step once '
        'they come', () {
      final early = Journal('earl-session');
      selection.showSession(early.data);
      expect(selection.stepId, isNull);
      early.step('collect', 1);
      selection.update([early.data]);
      expect(selection.stepId, 'earl-collect-0');
    });

    test('that changes nothing selected is not announced', () {
      final session = _session('olde-session', 0);
      selection.update([session]);
      notified = 0;
      selection.update([session]);
      expect(notified, 0);
    });
  });

  group('opening a session', () {
    test('selects its last step by first step-started', () {
      final session = a1b2();
      // A step that runs again keeps its place.
      session.events.add(StepStarted(time: at(400), stepId: 'a1b2-collect-0'));
      selection.showSession(session.data);
      expect(selected(), (false, 'a1b2-session', 'a1b2-notify-2'));
      expect(notified, 1);
    });

    test('Current graph selects no session or step', () {
      selection.showSession(a1b2().data);
      selection.showCurrentGraph();
      expect(selected(), (true, null, null));
    });
  });

  group('following (ui-spec «Logs»)', () {
    test('while the last step is selected, the new step is selected as it '
        'starts', () {
      final session = a1b2();
      selection.update([session.data]);
      expect(selection.stepId, 'a1b2-notify-2');
      expect(selection.following, isTrue);

      session.step('publish', 700);
      selection.update([session.data]);
      expect(selection.stepId, 'a1b2-publish-3');
    });

    test('selecting another step stops following; selecting the last one '
        'again resumes it', () {
      final session = a1b2();
      selection.update([session.data]);
      selection.selectStep(session.data, 'a1b2-collect-0');
      expect(selection.following, isFalse);
      session.step('publish', 700);
      selection.update([session.data]);
      expect(selection.stepId, 'a1b2-collect-0');

      selection.selectStep(session.data, 'a1b2-publish-3');
      expect(selection.following, isTrue);
      session.step('announce', 710);
      selection.update([session.data]);
      expect(selection.stepId, 'a1b2-announce-4');
    });
  });
}
