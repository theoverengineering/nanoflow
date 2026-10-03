import '../../layout/layout.dart';

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

/// What the selected session puts on the canvas, as the canvas asks for it.
/// The graph is drawn as it is: what a session's steps put on it is not
/// drawn yet, so every arrow, exit and bar is [Tone.plain].
final class CanvasMarks {
  const CanvasMarks._();

  static const plain = CanvasMarks._();

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
}
