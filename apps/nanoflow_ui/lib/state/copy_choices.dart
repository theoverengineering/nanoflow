/// The copies the user chose in the copies frames of a session's graph, and
/// the hints that tell copies apart (decision 11). Pure.
library;

import 'body_path.dart';
import 'copies.dart';
import 'outcomes.dart';

/// The copies chosen in the copies frames of one session's graph: by the
/// path to each frame's level, the id of the first step of the copy chosen
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
      depth: ?_chosen[_levelKey(path.take(depth))],
  };

  /// Chooses the copy [copyId] — the id of its first step; all for `null`
  /// — of the session [sessionId] in the frame at the level [depth] of
  /// [path].
  void choose(String sessionId, List<Opened> path, int depth, String? copyId) {
    keepFor(sessionId);
    final level = _levelKey(path.take(depth));
    _chosen = {
      for (final MapEntry(:key, :value) in _chosen.entries)
        if (key != level) key: value,
      level: ?copyId,
    };
  }

  /// The path to a level, as a key.
  static String _levelKey(Iterable<Opened> path) =>
      [for (final opened in path) '${opened.nodeId}#${opened.functionId ?? ''}']
          .join('/');
}

/// What the first step of [copy] gave, to tell the copy by (`copyHint`),
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
/// goes down through: the outputs of their first steps.
List<String> hintDocuments(ShownSteps shown) => [
  for (final frame in shown.frames)
    for (final copy in frame.copies) ?copy.hintDocument,
];
