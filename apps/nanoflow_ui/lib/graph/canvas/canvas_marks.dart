import '../../layout/layout.dart';
import '../../state/session_view.dart';

/// How an arrow, an exit or an input bar is drawn (docs/ui-spec.md «Граф»):
/// no way is highlighted, only what the code did not take is darker.
enum Tone {
  /// As the graph draws it.
  plain,

  /// An arrow out of a passed fork that no way of the code could have taken;
  /// in the body of one copy, what leads to or from a node the copy has not
  /// reached: darker.
  untaken,
}

/// What the selected session puts on the canvas, as the canvas asks for it
/// (spec §9 «Эффекты на графе», «Развилки», «Копии»): the marks of its
/// effects on the nodes of the level drawn and of the forks their code went
/// through, the nodes of the selected effect, how many copies a `copies` node
/// ran. [CanvasMarks.plain] for `Current graph`.
///
/// The way the code took is not highlighted: arrows, exits and bars are
/// [Tone.plain] — but an arrow out of a passed fork that no way of the code
/// could have taken is [Tone.untaken], except in the body of copies, all of
/// them shown, and in the bodies in it (decision 11); and in the body of one
/// copy, what leads to or from a node the copy has not reached is too
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
      allCopies: _inAll(view.frames),
      oneCopy: drawn && frame.selected != null,
    );
  }

  /// The marks of [scope] on the body of a frame drawn in place: as on
  /// that body opened; plain without a session.
  factory CanvasMarks.ofFrame(FrameScope? scope) {
    if (scope == null) return plain;
    return CanvasMarks._(
      scope.marks,
      allCopies: _inAll(scope.shown.frames),
      oneCopy: scope.copies?.selected != null,
    );
  }

  /// Whether a body under the copies [frames] is in the view of all copies:
  /// one of them shows all — copies in it cannot be chosen then.
  static bool _inAll(List<CopiesFrame> frames) =>
      frames.any((frame) => frame.selected == null);

  static const plain = CanvasMarks._(null);

  final GraphMarks? _marks;

  /// Whether the level drawn is the body of copies, all of them shown, or a
  /// body in it — a function opened from it, a call drawn in place: an
  /// effect node says how many copies are on it now, a fork no `2×`, and no
  /// arrow is darker for the forks the copies went through.
  final bool allCopies;

  /// Whether the level drawn is the body of copies, one copy shown: what
  /// leads to or from a node it has not reached is darker.
  final bool oneCopy;

  /// Whether there is no session: nothing is marked.
  bool get isPlain => _marks == null;

  /// Whether one copy is shown and has not reached the node [id].
  bool _unreached(String id) =>
      oneCopy && _marks?.of(id)?.state == NodeState.notVisited;

  /// The tone of the exits of [node].
  Tone exit(String node) => _unreached(node) ? Tone.untaken : Tone.plain;

  /// Whether [edge] leaves a passed fork where no way of the code could have
  /// gone, outside the view of all copies.
  bool _notTaken(EdgePath edge) =>
      !allCopies && (_marks?.passes.untaken(edge.edgeIndex) ?? false);

  /// The tone of [edge].
  Tone edge(EdgePath edge) =>
      _unreached(edge.from) || _unreached(edge.to) || _notTaken(edge)
      ? Tone.untaken
      : Tone.plain;

  /// The tone of the input bar of [node].
  Tone bar(String node) => _unreached(node) ? Tone.untaken : Tone.plain;

  /// The tone the legend shows back arrows in, the lightest they are drawn
  /// in; `null` when there are none of [back].
  Tone? backEdges(Iterable<EdgePath> back) {
    if (back.isEmpty) return null;
    return back.every((edge) => this.edge(edge) == Tone.untaken)
        ? Tone.untaken
        : Tone.plain;
  }

  /// What the effects put on the node [id]; `null` for `Current graph`, a
  /// fork the code did not go through, a marker.
  NodeMarks? node(String id) => _marks?.of(id);

  /// Whether the selected effect is on the node [id], or in it: it is ringed.
  bool selected(String id) => _marks?.selected.contains(id) ?? false;

  /// The badge over the stack of copies [id]: `×3` copies ran, `×0` none
  /// yet; [copiesBadge] for `Current graph`.
  String copies(String id) => switch (node(id)?.copies) {
    final n? => '×$n',
    null => copiesBadge,
  };
}
