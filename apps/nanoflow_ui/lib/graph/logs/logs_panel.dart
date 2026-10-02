import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../platform/shell.dart';
import '../../state/clock.dart';
import '../../state/graph_model.dart';
import '../../state/session_view.dart';
import '../../theme.dart';
import '../../widgets/clickable.dart';
import 'step_details_pane.dart';
import 'step_list.dart';

/// The `Logs` panel under the canvas (docs/ui-spec.md «Logs»): its title
/// names the selected run and its steps — `run e5f6 · 8 steps, 7 inherited
/// from k7f2` — over the [StepList] on the left and the selected step's
/// [StepDetailsPane] on the right. The chevron folds it to its title. With
/// `Current graph` selected, or no run, it is empty.
///
/// A click on a step selects it and asks the canvas to show its node
/// ([onRevealNode]); running times go on with the [clock].
class LogsPanel extends StatelessWidget {
  const LogsPanel({
    super.key,
    required this.model,
    required this.clock,
    required this.shell,
    required this.graphFile,
    required this.collapsed,
    required this.onToggle,
    required this.onRevealNode,
    this.onOpenStep,
  });

  final GraphModel model;
  final LiveClock clock;
  final Shell shell;

  /// The graph file: the paths of files are shown from its directory.
  final String graphFile;

  /// Whether the panel is folded to its title.
  final bool collapsed;

  /// Folds or unfolds the panel.
  final VoidCallback onToggle;

  /// Brings the node of a clicked step into view on the canvas.
  final ValueChanged<String> onRevealNode;

  /// Opens the step details window for a node: `Open`.
  final ValueChanged<String>? onOpenStep;

  static const titleKey = ValueKey('logs title');
  static const toggleKey = ValueKey('logs toggle');

  /// The panel's height folded, with the border over it.
  static const foldedExtent = 39.0;

  /// The steps list's width, as in the mockups, while the step's details
  /// keep [_leastDetails].
  static const _listWidth = 548.0;
  static const _leastDetails = 320.0;
  static const _leastList = 300.0;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.panel,
    child: ListenableBuilder(
      listenable: Listenable.merge([model, clock]),
      builder: (context, _) {
        final view = model.sessionView(clock.now());
        final run = view?.run;
        final step = view?.step;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Title(
              header: run?.header,
              collapsed: collapsed,
              onToggle: onToggle,
            ),
            if (!collapsed && run != null)
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final list = math.max(
                      _leastList,
                      math.min(
                        _listWidth,
                        constraints.maxWidth - _leastDetails,
                      ),
                    );
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: list - 1,
                          child: StepList(
                            rows: run.rows,
                            scale: run.scale,
                            selectedStepId: step?.stepId,
                            following: model.selection.following,
                            onSelect: (row) {
                              model.selectStep(row.stepId);
                              onRevealNode(row.name);
                            },
                            onSelectRun: model.selectRun,
                          ),
                        ),
                        const SizedBox(
                          width: 1,
                          child: ColoredBox(color: AppColors.divider),
                        ),
                        Expanded(
                          child: step == null
                              ? const SizedBox.shrink()
                              : StepDetailsPane(
                                  step: step,
                                  files: model.files,
                                  shell: shell,
                                  graphFile: graphFile,
                                  onOpenStep: onOpenStep,
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// The chevron and `Logs`, which fold the panel, and the selected run with
/// its steps.
class _Title extends StatelessWidget {
  const _Title({
    required this.header,
    required this.collapsed,
    required this.onToggle,
  });

  final LogsHeader? header;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final header = this.header;
    final parent = header?.inheritedFrom;
    return Container(
      key: LogsPanel.titleKey,
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        spacing: 10,
        children: [
          Clickable(
            key: LogsPanel.toggleKey,
            onTap: onToggle,
            child: Row(
              spacing: 10,
              children: [
                Transform.rotate(
                  angle: collapsed ? -math.pi / 2 : 0,
                  child: CustomPaint(
                    size: const Size.square(12),
                    painter: _ChevronPainter(),
                  ),
                ),
                Text('Logs', style: AppText.logsTitle),
              ],
            ),
          ),
          if (header != null)
            Expanded(
              child: Row(
                children: [
                  Text('run ', style: AppText.logsRun),
                  Tooltip(
                    message: header.runId,
                    child: Text(
                      header.shortId,
                      style: AppText.logsRunId.copyWith(
                        color: AppColors.accentText,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      ' · ${header.stepsLead}',
                      style: AppText.logsRun,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (header.parentId case final parentId? when parent != null)
                    Tooltip(
                      message: parentId,
                      child: Text(parent, style: AppText.logsRunId),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The mockup's chevron, pointing down: 12 units.
class _ChevronPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..scale(size.width / 12)
      ..drawPath(
        Path()
          ..moveTo(3, 4.5)
          ..lineTo(6, 7.5)
          ..lineTo(9, 4.5),
        Paint()
          ..color = AppColors.textMuted
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(_ChevronPainter old) => false;
}
