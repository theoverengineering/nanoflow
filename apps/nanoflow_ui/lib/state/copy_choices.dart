/// The copies the user chose in the copies frames of a session's graph, and
/// the hints that tell copies apart (decision 11). Pure.
library;

import 'body_path.dart';
import 'copies.dart';
import 'outcomes.dart';

/// The copies chosen in the copies frames of one session's graph: by the
/// path to each frame's level, the id of the first effect of the copy chosen
/// there. They are forgotten for another session.
final class CopyChoices {
  Map<String, String> _chosen = const {};
  String? _sessionId;

  /// Forgets the copies chosen unless they are of the session [sessionId].
  void keepFor(String? sessionId) {
    if (sessionId == _sessionId) return;
    _chosen = const {};
    _sessionId = sessionId;
  }

  /// Whether a copy of the session [sessionId] is chosen in any frame.
  bool anyFor(String sessionId) =>
      sessionId == _sessionId && _chosen.isNotEmpty;

  /// The copies chosen in the frames of the levels [path] goes down
  /// through, by the depth of each level.
  Map<int, String> on(List<Opened> path) => {
    for (var depth = 1; depth <= path.length; depth++)
      depth: ?_chosen[levelKey(path.take(depth))],
  };

  /// Chooses the copy [copyId] — the id of its first effect; all for `null`
  /// — of the session [sessionId] in the frame at the level [depth] of
  /// [path].
  void choose(String sessionId, List<Opened> path, int depth, String? copyId) {
    keepFor(sessionId);
    final level = levelKey(path.take(depth));
    _chosen = {
      for (final MapEntry(:key, :value) in _chosen.entries)
        if (key != level) key: value,
      level: ?copyId,
    };
  }

  /// Of the frames at [paths], the one where a copy of the session
  /// [sessionId] was chosen last; `null` when none has one chosen.
  List<Opened>? lastChosen(String sessionId, Iterable<List<Opened>> paths) {
    if (sessionId != _sessionId) return null;
    final byKey = {for (final path in paths) levelKey(path): path};
    for (final key in _chosen.keys.toList().reversed) {
      if (byKey[key] case final path?) return path;
    }
    return null;
  }
}

/// What the first effect of [copy] gave, to tell the copy by (`copyHint`),
/// as [documents] know it; `null` while it is not known.
String? hintOf(Copy copy, KnownOutcomes documents) {
  final document = copy.hintDocument;
  if (document == null) return null;
  return switch (documents[document]) {
    (:final value) => copyHint(value),
    null => null,
  };
}

/// The documents whose values hint at the copies of the frames [shown]
/// goes down through: the outputs of their first effects.
List<String> hintDocuments(ShownEffects shown) => [
  for (final frame in shown.frames)
    for (final copy in frame.copies) ?copy.hintDocument,
];
