import '../../layout/layout.dart';
import '../../state/session_view.dart';

/// How an arrow, an exit or an input bar is drawn (docs/ui-spec.md «Граф»).
/// A session's tones go from the darkest to the one drawn over the rest.
enum Tone {
  /// `Current graph`: no session, so nothing was gone along.
  plain,

  /// No run of the session went along it: darker.
  untaken,

  /// Runs of the session went along it, the selected run did not.
  taken,

  /// The selected run went along it: the accent color.
  path,
}

/// What the selected session puts on the canvas, as the canvas asks for it.
/// [CanvasMarks.plain] for `Current graph`: no states, runs or counters.
final class CanvasMarks {
  const CanvasMarks._(this._marks, this._path, this.selectedNode, this.runId);

  /// The marks of [view]; plain without a session.
  factory CanvasMarks.of(SessionView? view) => view == null
      ? plain
      : CanvasMarks._(
          view.marks,
          view.run?.path,
          view.selectedNode,
          view.run?.chip.runId,
        );

  static const plain = CanvasMarks._(null, null, null, null);

  final GraphMarks? _marks;
  final RunPath? _path;

  /// The node of the selected step: ringed.
  final String? selectedNode;

  /// The selected run.
  final String? runId;

  bool get isPlain => _marks == null;

  /// The tone of the exit [index] of [node] and of its stub.
  Tone exit(String node, int index) {
    final marks = _marks;
    if (marks == null) return Tone.plain;
    if (_path?.exits.contains((node: node, exit: index)) ?? false) {
      return Tone.path;
    }
    return marks.isTaken(node, index) ? Tone.taken : Tone.untaken;
  }

  /// The tone of [edge].
  Tone edge(EdgePath edge) {
    final marks = _marks;
    if (marks == null) return Tone.plain;
    final arrow = (from: edge.from, exit: edge.exitIndex, to: edge.to);
    if (_path?.arrows.contains(arrow) ?? false) return Tone.path;
    return marks.isTaken(edge.from, edge.exitIndex) ? Tone.taken : Tone.untaken;
  }

  /// The tone of the input bar of [node], which [into] arrive at: the
  /// selected run's if it entered the node, else the lightest of theirs.
  Tone bar(String node, Iterable<EdgePath> into) {
    if (_marks == null) return Tone.plain;
    if (_path?.inputs.contains(node) ?? false) return Tone.path;
    return into.any((edge) => this.edge(edge) != Tone.untaken)
        ? Tone.taken
        : Tone.untaken;
  }

  /// The tone the legend shows back arrows in: the selected run's if it
  /// went along one of [back], else the lightest they are drawn in; `null`
  /// when there are none.
  Tone? backEdges(Iterable<EdgePath> back) {
    Tone? lightest;
    for (final edge in back) {
      final tone = this.edge(edge);
      if (lightest == null || tone.index > lightest.index) lightest = tone;
    }
    return lightest;
  }

  /// `2×` on an exit runs went through; `null` otherwise.
  String? counter(String node, int index) => _marks?.counterOf(node, index);

  /// The node's state; `null` for `Current graph`.
  NodeState? state(String node) => _marks?.stateOf(node);

  /// The runs on [node], in the order they were created.
  List<RunMarker> markers(String node) => _marks?.markersOn(node) ?? const [];

  /// `2×` over a node entered more than once.
  String? visits(String node) => _marks?.visitText(node);
}
