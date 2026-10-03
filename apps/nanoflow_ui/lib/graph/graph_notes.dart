import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../state/graph_model.dart';
import '../theme.dart';
import '../widgets/dot.dart';

/// What to know of the graph on the canvas (spec §9 «Свежесть», «Сессия»;
/// docs/ui-spec.md «Когда что-то не так»), over the top left of the canvas:
/// for `Current graph`, the graph file gone or not readable, the graph that
/// may not match the code with the files that changed, the graph file's
/// warnings; for a session, a session without a snapshot, one that ran on
/// other code or whose code was not checked. Which notes there are is
/// decided by the model (`CanvasGraph.notes`); here they are drawn.
///
/// The text can be selected and copied.
///
/// [onHeight] hears how tall they are, 0 once there are none: the canvas
/// keeps the graph clear of them.
class GraphNotes extends StatelessWidget {
  const GraphNotes({super.key, required this.notes, this.onHeight});

  final List<GraphNote> notes;

  final ValueChanged<double>? onHeight;

  /// How wide the notes get.
  static const _width = 640.0;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: _Measured(
      onHeight: onHeight,
      child: notes.isEmpty
          ? const SizedBox.shrink()
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _width),
              child: SelectionArea(
                child: SingleChildScrollView(
                  // One width for all, the widest one's.
                  child: IntrinsicWidth(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 8,
                      children: [for (final note in notes) _Banner(note)],
                    ),
                  ),
                ),
              ),
            ),
    ),
  );
}

/// [child], whose height [onHeight] hears after each layout that changes it.
class _Measured extends SingleChildRenderObjectWidget {
  const _Measured({required this.onHeight, required super.child});

  final ValueChanged<double>? onHeight;

  @override
  _RenderMeasured createRenderObject(BuildContext context) =>
      _RenderMeasured(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured renderObject) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured(this.onHeight);

  ValueChanged<double>? onHeight;

  /// Nothing over the canvas is what the canvas starts with.
  double _told = 0;

  @override
  void performLayout() {
    super.performLayout();
    final height = child?.size.height ?? 0;
    if (height == _told) return;
    _told = height;
    // Told after the frame: a layout may not change what is being built.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached && _told == height) onHeight?.call(height);
    });
  }
}

/// One note: a dot and its title, red when it is a danger, else amber;
/// under it its lines (errors, paths, warnings) and its text.
class _Banner extends StatelessWidget {
  const _Banner(this.note);

  final GraphNote note;

  @override
  Widget build(BuildContext context) {
    final GraphNote(:title, :danger, :lines, :text) = note;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 14, 9),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(
          color: danger ? AppColors.dangerBorder : AppColors.runningBorder,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 5,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Dot(danger ? AppColors.failed : AppColors.running),
              Flexible(
                child: Text(
                  title,
                  style: AppText.problemTitle.copyWith(
                    color: danger ? AppColors.dangerText : AppColors.running,
                  ),
                ),
              ),
            ],
          ),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(left: 15),
              child: Text(line, style: AppText.problemCode),
            ),
          if (text != null)
            Padding(
              padding: const EdgeInsets.only(left: 15),
              child: Text(text, style: AppText.problemText),
            ),
        ],
      ),
    );
  }
}
