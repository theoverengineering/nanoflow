import '../../layout/layout.dart';
import '../../state/session_view.dart';

/// How an arrow, an exit or an input bar is drawn (docs/ui-spec.md «Граф»):
/// no way is highlighted, only what the code did not take is darker.
enum Tone {
  /// As the graph draws it.
  plain,

  /// An arrow out of a passed fork that no way of the code could have taken:
  /// darker.
  untaken,
}

/// What the selected session puts on the canvas, as the canvas asks for it
/// (spec §9 «Эффекты на графе», «Развилки»): the marks of its effects on the
/// nodes of the level drawn and of the forks their code went through, the
/// nodes of the selected effect. [CanvasMarks.plain] for `Current graph`.
///
/// The way the code took is not highlighted: arrows, exits and bars are
/// [Tone.plain] — but an arrow out of a passed fork that no way of the code
/// could have taken is [Tone.untaken].
final class CanvasMarks {
  const CanvasMarks._(this._marks);

  /// The marks of [view] on the level drawn; plain without a session.
  factory CanvasMarks.of(SessionView? view) {
    final marks = view?.marks;
    return marks == null ? plain : CanvasMarks._(marks);
  }

  /// The marks of [scope] on the body of a frame drawn in place: as on
  /// that body opened; plain without a session.
  factory CanvasMarks.ofFrame(FrameScope? scope) =>
      scope == null ? plain : CanvasMarks._(scope.marks);

  static const plain = CanvasMarks._(null);

  final GraphMarks? _marks;

  /// Whether there is no session: nothing is marked.
  bool get isPlain => _marks == null;

  /// The tone of [edge]: [Tone.untaken] when it leaves a passed fork where
  /// no way of the code could have gone.
  Tone edge(EdgePath edge) => _marks?.passes.untaken(edge.edgeIndex) ?? false
      ? Tone.untaken
      : Tone.plain;

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
}
