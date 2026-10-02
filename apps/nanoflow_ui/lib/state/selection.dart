import 'package:flutter/foundation.dart';

import 'session_feed.dart';
import 'session_view.dart';

/// What is selected on the graph screen: `Current graph` or a session, the
/// session's run, and a step among the run's steps (docs/ui-spec.md «Выбор»,
/// «Logs»).
///
/// The data comes in through [update]; new data never resets a choice. Only
/// while the feed is still loading what is on disk, and nobody has chosen
/// yet, does the selection follow the newest session.
class Selection extends ChangeNotifier {
  bool _currentGraph = true;
  String? _sessionId;
  String? _runId;
  String? _stepId;
  bool _following = true;

  /// Whether the choice made on opening the graph is over: the feed has
  /// loaded, or the user has chosen.
  bool _settled = false;

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

  /// Takes in [sessions] as the feed has them now; [loading] while the feed
  /// is still giving what was on disk.
  ///
  /// On opening the graph the newest session is selected, or `Current graph`
  /// when there is none. After that, new data only fills in what is missing
  /// (the run of a session opened before its runs came) and moves a
  /// following selection on to a new step.
  void update(Iterable<SessionData> sessions, {required bool loading}) =>
      _change(() {
        if (!_settled) {
          final newest = sessionsNewestFirst(sessions).firstOrNull;
          if (newest == null) {
            _showCurrentGraph();
          } else {
            _open(newest);
          }
          _settled = !loading;
          return;
        }
        final session = sessions.where((s) => s.id == _sessionId).firstOrNull;
        if (session == null) return;
        if (_runId == null) {
          _open(session);
        } else if (_following) {
          _stepId = stepsOfRun(session, _runId!).lastOrNull?.stepId ?? _stepId;
        }
      });

  /// Selects `Current graph`: the current graph, without a session.
  void showCurrentGraph() => _change(() {
    _settled = true;
    _showCurrentGraph();
  });

  /// Opens [session]: its first running run, else its first failed run, else
  /// its last run by time, and that run's last step.
  void showSession(SessionData session) => _change(() {
    _settled = true;
    if (_currentGraph || _sessionId != session.id) _open(session);
  });

  /// Selects the run [runId] of [session] and its last step.
  void selectRun(SessionData session, String runId) => _change(() {
    _settled = true;
    _runId = runId;
    _selectLastStep(session);
  });

  /// Selects the step [stepId] of the selected run; following goes on only
  /// when it is the run's last step.
  void selectStep(SessionData session, String stepId) => _change(() {
    _settled = true;
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

  void _open(SessionData session) {
    _currentGraph = false;
    _sessionId = session.id;
    final runs = runsInOrder(session);
    RunData? first(RunPhase phase) =>
        runs.where((run) => phaseOf(run) == phase).firstOrNull;
    _runId =
        (first(RunPhase.running) ?? first(RunPhase.failed) ?? runs.lastOrNull)
            ?.id;
    _selectLastStep(session);
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
