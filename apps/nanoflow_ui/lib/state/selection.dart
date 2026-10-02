import 'package:flutter/foundation.dart';

import 'session_feed.dart';
import 'session_view.dart';

/// What is selected on the graph screen: `Current graph` or a session, the
/// session's run, and a step among the run's steps (docs/ui-spec.md «Выбор»,
/// «Logs»).
///
/// The data comes in through [update], in whatever order the feed gives it;
/// new data never resets a choice. Until the user chooses, the newest session
/// started before the graph was opened is selected, and in it the run that
/// opening it then picks ([openingRun]): what started later never takes the
/// selection.
class Selection extends ChangeNotifier {
  /// [now] tells when the graph is opened and when the user opens a session.
  Selection({DateTime Function()? now}) : _now = now ?? DateTime.now {
    openedAt = _now();
  }

  final DateTime Function() _now;

  /// When the graph was opened.
  late final DateTime openedAt;

  bool _currentGraph = true;
  String? _sessionId;
  String? _runId;
  String? _stepId;
  bool _following = true;

  /// Whether the user has chosen what to show: `Current graph` or a session.
  bool _sessionChosen = false;

  /// Whether the user has chosen the run, or a step of it.
  bool _runChosen = false;

  /// When the selected session was opened: the run is the one [openingRun]
  /// picks for that moment until the user chooses another.
  DateTime? _sessionOpenedAt;

  /// Whether `Current graph` is selected rather than a session.
  bool get currentGraph => _currentGraph;

  String? get sessionId => _sessionId;

  /// The selected run of the selected session; `null` when it has none yet.
  String? get runId => _runId;

  /// The selected step among the run's steps, inherited ones too; `null`
  /// when it has none yet.
  String? get stepId => _stepId;

  /// Whether the selection moves on to each new step of the run: it does
  /// while the run's last step is selected.
  bool get following => _following;

  /// Takes in [sessions] as the feed has them now.
  void update(Iterable<SessionData> sessions) => _change(() {
    if (!_sessionChosen) {
      final newest = sessionsNewestFirst(sessions)
          .where((s) => sessionStart(s)!.isBefore(openedAt))
          .firstOrNull;
      if (newest == null) {
        _showCurrentGraph();
        return;
      }
      if (_currentGraph || _sessionId != newest.id) _open(newest, openedAt);
    }
    final session = sessions.where((s) => s.id == _sessionId).firstOrNull;
    if (session != null) _refresh(session);
  });

  /// Selects `Current graph`: the current graph, without a session.
  void showCurrentGraph() => _change(() {
    _sessionChosen = true;
    _showCurrentGraph();
  });

  /// Opens [session]: its first running run, else its first failed run, else
  /// its last run by time, and that run's last step.
  void showSession(SessionData session) => _change(() {
    _sessionChosen = true;
    if (!_currentGraph && _sessionId == session.id) return;
    _open(session, _now());
    _refresh(session);
  });

  /// Selects the run [runId] of [session] and its last step.
  void selectRun(SessionData session, String runId) => _change(() {
    _sessionChosen = true;
    _runChosen = true;
    _runId = runId;
    _selectLastStep(session);
  });

  /// Selects the step [stepId] of the selected run; following goes on only
  /// when it is the run's last step.
  void selectStep(SessionData session, String stepId) => _change(() {
    _sessionChosen = true;
    _runChosen = true;
    _stepId = stepId;
    final runId = _runId;
    _following =
        runId != null &&
        stepsOfRun(session, runId).lastOrNull?.stepId == stepId;
  });

  /// Selects the last step on [node] among the selected run's steps,
  /// inherited ones too; nothing happens when there is none.
  void clickNode(SessionData session, String node) {
    final runId = _runId;
    if (runId == null) return;
    final step = stepsOfRun(
      session,
      runId,
    ).where((step) => step.node == node).lastOrNull;
    if (step != null) selectStep(session, step.stepId);
  }

  void _showCurrentGraph() {
    _currentGraph = true;
    _sessionId = null;
    _runId = null;
    _stepId = null;
    _following = true;
  }

  void _open(SessionData session, DateTime at) {
    _currentGraph = false;
    _sessionId = session.id;
    _sessionOpenedAt = at;
    _runChosen = false;
    _runId = null;
    _stepId = null;
    _following = true;
  }

  /// Brings the selection in [session] up to its data: the run opening it
  /// picks, unless the user chose one; the new last step, while following.
  void _refresh(SessionData session) {
    if (!_runChosen) {
      final run = openingRun(session, _sessionOpenedAt!)?.id;
      if (run != _runId) {
        _runId = run;
        _selectLastStep(session);
        return;
      }
    }
    final runId = _runId;
    if (_following && runId != null) {
      _stepId = stepsOfRun(session, runId).lastOrNull?.stepId ?? _stepId;
    }
  }

  void _selectLastStep(SessionData session) {
    final runId = _runId;
    _stepId = runId == null
        ? null
        : stepsOfRun(session, runId).lastOrNull?.stepId;
    _following = true;
  }

  /// Runs [change] and tells listeners when it changed what is selected.
  void _change(void Function() change) {
    final before = _selected;
    change();
    if (_selected != before) notifyListeners();
  }

  (bool, String?, String?, String?, bool) get _selected =>
      (_currentGraph, _sessionId, _runId, _stepId, _following);
}
