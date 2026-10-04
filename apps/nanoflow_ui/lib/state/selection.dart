import 'package:flutter/foundation.dart';

import 'session_feed.dart';
import 'sessions.dart';

/// What is selected on the graph screen: `Current graph` or a session, and
/// an effect among the session's effects (docs/ui-spec.md «Выбор», «Logs»).
///
/// The data comes in through [update], in whatever order the feed gives it;
/// new data never resets a choice. Until the user chooses, the newest
/// session started before the graph was opened is selected, on its last
/// effect: what started later never takes the selection.
class Selection extends ChangeNotifier {
  /// [now] tells when the graph is opened.
  Selection({DateTime Function()? now}) : _now = now ?? DateTime.now {
    _openedAt = _now();
  }

  final DateTime Function() _now;

  /// The last of the effects of a session shown, which following moves on
  /// to; `null` for the session's last effect. The effects shown are those of
  /// the copies chosen, when any is.
  String? Function(SessionData session)? lastEffectOf;

  late DateTime _openedAt;

  bool _currentGraph = true;
  String? _sessionId;
  String? _effectId;
  bool _following = true;

  /// Whether the user has chosen what to show: `Current graph` or a session.
  bool _sessionChosen = false;

  /// When the graph was opened, or opened again for another workflow.
  DateTime get openedAt => _openedAt;

  /// Whether `Current graph` is selected rather than a session.
  bool get currentGraph => _currentGraph;

  String? get sessionId => _sessionId;

  /// The selected effect of the selected session; `null` when it has none
  /// yet.
  String? get effectId => _effectId;

  /// Whether the selection moves on to each new effect of the session: it
  /// does while the session's last effect is selected.
  bool get following => _following;

  /// Takes in [sessions] as the feed has them now.
  void update(Iterable<SessionData> sessions) => _change(() {
    if (!_sessionChosen) {
      final newest = sessionsNewestFirst(sessions)
          .where((s) => s.state.startedAt!.isBefore(_openedAt))
          .firstOrNull;
      if (newest == null) {
        _showCurrentGraph();
        return;
      }
      if (_currentGraph || _sessionId != newest.id) _open(newest);
    }
    final session = sessions.where((s) => s.id == _sessionId).firstOrNull;
    if (session != null) _refresh(session);
  });

  /// Forgets what the user chose, as when the graph is opened now: for
  /// another workflow, whose sessions are others. The next [update] selects.
  void reopen() => _change(() {
    _openedAt = _now();
    _sessionChosen = false;
    _showCurrentGraph();
  });

  /// Selects `Current graph`: the graph file, without a session.
  void showCurrentGraph() => _change(() {
    _sessionChosen = true;
    _showCurrentGraph();
  });

  /// Opens [session] on its last effect.
  void showSession(SessionData session) => _change(() {
    _sessionChosen = true;
    if (!_currentGraph && _sessionId == session.id) return;
    _open(session);
  });

  /// Selects the effect [effectId] of [session]; following goes on only when it
  /// is the session's last effect.
  void selectEffect(SessionData session, String effectId) => _change(() {
    _sessionChosen = true;
    _effectId = effectId;
    _following = _lastEffect(session) == effectId;
  });

  void _showCurrentGraph() {
    _currentGraph = true;
    _sessionId = null;
    _effectId = null;
    _following = true;
  }

  void _open(SessionData session) {
    _currentGraph = false;
    _sessionId = session.id;
    _effectId = _lastEffect(session);
    _following = true;
  }

  /// Brings the selection in [session] up to its data: the new last effect,
  /// while following.
  void _refresh(SessionData session) {
    if (_following) _effectId = _lastEffect(session) ?? _effectId;
  }

  /// The last of the effects of [session] shown ([lastEffectOf]); by default
  /// the effect that started first last.
  String? _lastEffect(SessionData session) =>
      lastEffectOf?.call(session) ?? _lastOf(session);

  static String? _lastOf(SessionData session) =>
      session.state.effects.lastOrNull?.effectId;

  /// Runs [change] and tells listeners when it changed what is selected.
  void _change(void Function() change) {
    final before = _selected;
    change();
    if (_selected != before) notifyListeners();
  }

  (bool, String?, String?, bool) get _selected =>
      (_currentGraph, _sessionId, _effectId, _following);
}
