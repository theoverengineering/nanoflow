import '../../layout/layout.dart';
import '../../state/session_view.dart';

/// How an arrow, an exit or an input bar is drawn (docs/ui-spec.md «Граф»).
/// A session's tones go from the darkest to the one drawn over the rest.
enum Tone {
  /// `Current graph`: no session, so nothing was gone along.
  plain,

  /// No step of the session went along it: darker.
  untaken,

  /// Steps of the session went along it.
  taken,

  /// The selected way went along it: the accent color.
  path,
}

/// What the selected session puts on the canvas, as the canvas asks for it
/// (spec §9 «Шаги на графе», «Копии»): the marks of its steps on the nodes
/// of the level drawn, the nodes of the selected step, how many copies a
/// `copies` node ran. [CanvasMarks.plain] for `Current graph`.
///
/// A step records no way it took, only where it was called: arrows, exits
/// and bars are [Tone.plain] — but in the body of one copy, what leads to
/// or from a node the copy has not reached is [Tone.untaken]
/// (docs/design/code-first/copy-switcher.html).
final class CanvasMarks {
  const CanvasMarks._(
    this._marks, {
    this.allCopies = false,
    this.oneCopy = false,
  });

  /// The marks of [view] on the level drawn, [depth]; plain without a
  /// session.
  factory CanvasMarks.of(SessionView? view, {required int depth}) {
    final marks = view?.marks;
    if (marks == null) return plain;
    final frame = view!.frames.lastOrNull;
    final drawn = frame != null && frame.depth == depth;
    return CanvasMarks._(
      marks,
      allCopies: drawn && frame.selected == null,
      oneCopy: drawn && frame.selected != null,
    );
  }

  /// The marks of [scope] on the body of a frame drawn in place: as on
  /// that body opened; plain without a session.
  factory CanvasMarks.ofFrame(FrameScope? scope) {
    if (scope == null) return plain;
    final copies = scope.copies;
    return CanvasMarks._(
      scope.marks,
      allCopies: copies != null && copies.selected == null,
      oneCopy: copies?.selected != null,
    );
  }

  static const plain = CanvasMarks._(null);

  final GraphMarks? _marks;

  /// Whether the level drawn is the body of copies, all of them shown: a
  /// step node says how many copies are on it now.
  final bool allCopies;

  /// Whether the level drawn is the body of copies, one copy shown: what
  /// leads to or from a node it has not reached is darker.
  final bool oneCopy;

  /// Whether there is no session: nothing is marked.
  bool get isPlain => _marks == null;

  /// Whether one copy is shown and has not reached the node [id].
  bool _unreached(String id) =>
      oneCopy && _marks?.of(id)?.state == NodeState.notVisited;

  /// The tone of the exit [index] of [node].
  Tone exit(String node, int index) =>
      _unreached(node) ? Tone.untaken : Tone.plain;

  /// The tone of [edge].
  Tone edge(EdgePath edge) =>
      _unreached(edge.from) || _unreached(edge.to) ? Tone.untaken : Tone.plain;

  /// The tone of the input bar of [node], which [into] arrive at.
  Tone bar(String node, Iterable<EdgePath> into) =>
      _unreached(node) ? Tone.untaken : Tone.plain;

  /// The tone the legend shows back arrows in, the lightest they are drawn
  /// in; `null` when there are none of [back].
  Tone? backEdges(Iterable<EdgePath> back) {
    if (back.isEmpty) return null;
    return back.every((edge) => this.edge(edge) == Tone.untaken)
        ? Tone.untaken
        : Tone.plain;
  }

  /// What the steps put on the node [id]; `null` for `Current graph`, a
  /// condition, a marker.
  NodeMarks? node(String id) => _marks?.of(id);

  /// Whether the selected step is on the node [id], or in it: it is ringed.
  bool selected(String id) => _marks?.selected.contains(id) ?? false;

  /// The badge over the stack of copies [id]: `×3` copies ran, `×0` none
  /// yet; [copiesBadge] for `Current graph`.
  String copies(String id) => switch (node(id)?.copies) {
    final n? => '×$n',
    null => copiesBadge,
  };
}
