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
/// A step records no way it took, only where it was called: every arrow,
/// exit and bar is [Tone.plain].
final class CanvasMarks {
  const CanvasMarks._(this._marks, {this.allCopies = false});

  /// The marks of [view] on the level drawn; plain without a session.
  factory CanvasMarks.of(SessionView? view, {required int depth}) {
    final marks = view?.marks;
    if (marks == null) return plain;
    final frame = view!.frames.lastOrNull;
    return CanvasMarks._(
      marks,
      allCopies:
          frame != null && frame.depth == depth && frame.selected == null,
    );
  }

  static const plain = CanvasMarks._(null);

  final GraphMarks? _marks;

  /// Whether the level drawn is the body of copies, all of them shown: a
  /// step node says how many copies are on it now.
  final bool allCopies;

  /// Whether there is no session: nothing is marked.
  bool get isPlain => _marks == null;

  /// The tone of the exit [index] of [node].
  Tone exit(String node, int index) => Tone.plain;

  /// The tone of [edge].
  Tone edge(EdgePath edge) => Tone.plain;

  /// The tone of the input bar of [node], which [into] arrive at.
  Tone bar(String node, Iterable<EdgePath> into) => Tone.plain;

  /// The tone the legend shows back arrows in, the lightest they are drawn
  /// in; `null` when there are none of [back].
  Tone? backEdges(Iterable<EdgePath> back) => back.isEmpty ? null : Tone.plain;

  /// `2×` on an exit the flow went through; `null` otherwise.
  String? counter(String node, int index) => null;

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
