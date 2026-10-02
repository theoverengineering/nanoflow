import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;

import '../state/graph_model.dart';
import '../state/graph_source.dart';
import '../state/texts.dart' show count;
import '../theme.dart';
import '../widgets/dot.dart';

/// The head of the errors of a description that fails check.
String checkFailed(int errors) =>
    'nanoflow check found ${count(errors, 'error')}';

/// Said under the errors while the canvas shows the last graph that passed.
const lastValidGraphShown = 'The canvas shows the last graph that passed.';

/// Said under [fileUnavailable]: what was read of [fileName] stays.
String fileUnavailableDetail(String fileName) =>
    '$fileName is gone; the canvas keeps the last graph read from it.';

/// What is wrong with the current graph (docs/ui-spec.md «Когда что-то не
/// так»), over the top left of the canvas while `Current graph` is selected:
/// the graph file gone, its program missing or exited, `nanoflow` missing to
/// check it, and the errors `nanoflow check` found. The canvas under it
/// shows the last graph that passed check, or `No valid graph yet`. Over a
/// session the canvas shows the session's own graph, and nothing is here.
///
/// The text can be selected and copied.
///
/// [onHeight] hears how tall they are, 0 when there are none: the canvas
/// keeps the graph clear of them.
class GraphProblems extends StatelessWidget {
  const GraphProblems({super.key, required this.model, this.onHeight});

  final GraphModel model;

  final ValueChanged<double>? onHeight;

  /// How wide the problems get.
  static const _width = 640.0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => Align(
      alignment: Alignment.topLeft,
      child: _Measured(
        onHeight: onHeight,
        child: _problems() ?? const SizedBox.shrink(),
      ),
    ),
  );

  /// The banners, one width for all, the widest one's; `null` when there are
  /// none.
  Widget? _problems() {
    if (!model.selection.currentGraph) return null;
    final source = model.source;
    final canvas = model.canvas;
    final problem = source.programProblem;
    final checkProblem = source.checkProblem;
    final banners = [
      if (source.fileMissing)
        _Banner(
          danger: true,
          title: fileUnavailable,
          text: fileUnavailableDetail(p.basename(source.file)),
        ),
      if (problem != null)
        _Banner(
          title: problem.message,
          code: [if (problem.details.isNotEmpty) problem.details],
        ),
      if (checkProblem != null) _Banner(title: checkProblem),
      if (canvas.errors.isNotEmpty)
        _Banner(
          danger: true,
          title: checkFailed(canvas.errors.length),
          code: canvas.errors,
          text: canvas.graph == null ? null : lastValidGraphShown,
        ),
    ];
    if (banners.isEmpty) return null;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _width),
      child: SelectionArea(
        child: SingleChildScrollView(
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: banners,
            ),
          ),
        ),
      ),
    );
  }
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
  double? _told;

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

/// One thing wrong: a dot and a [title] in red when [danger], else amber;
/// under it [code] (errors, a program's last words) and a [text].
class _Banner extends StatelessWidget {
  const _Banner({
    required this.title,
    this.danger = false,
    this.code = const [],
    this.text,
  });

  final String title;
  final bool danger;
  final List<String> code;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final text = this.text;
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
          for (final line in code)
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
