import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../platform/shell.dart';
import '../../state/clock.dart';
import '../../state/graph_model.dart';
import '../../state/session_view.dart';
import '../../theme.dart';
import '../../widgets/clickable.dart';
import 'effect_details_pane.dart';
import 'effect_list.dart';

/// The `Logs` panel under the canvas (docs/ui-spec.md «Logs»; spec §9
/// «Логи»): its title counts the effects shown and names the copy shown —
/// `12 effects`, `pkg 2 · 3 effects` — over the [EffectList] on the left and
/// the selected effect's [EffectDetailsPane] on the right. The chevron folds it
/// to its title. With `Current graph` selected it is empty.
///
/// A click on an effect selects it and asks the canvas to show its node on
/// the level drawn, or the call or copies it is in — its node in their
/// frame, when they are drawn in place ([onRevealNode]);
/// running times go on with the [clock].
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
    this.onOpenEffect,
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

  /// Brings the node [id] of a clicked effect into view on the canvas.
  final ValueChanged<String> onRevealNode;

  /// Opens the effect details window on the selected effect: `Open`.
  final ValueChanged<EffectDetails>? onOpenEffect;

  static const titleKey = ValueKey('logs title');
  static const toggleKey = ValueKey('logs toggle');

  /// The panel's height folded, with the border over it.
  static const foldedExtent = 39.0;

  /// The effects list's width, as in the mockups, while the effect's details
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
        final logs = view?.logs;
        final effect = view?.effect;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Title(
              header: logs?.header,
              collapsed: collapsed,
              onToggle: onToggle,
            ),
            if (!collapsed && view != null && logs != null)
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
                          child: EffectList(
                            rows: logs.rows,
                            scale: logs.scale,
                            selectedEffectId: effect?.effectId,
                            following: model.selection.following,
                            onSelect: (row) {
                              model.selectEffect(row.effectId);
                              final nodes = view.revealPathOf(row.effectId);
                              if (nodes.isNotEmpty) {
                                onRevealNode(nodes.join('/'));
                              }
                            },
                            onToggleRun: model.toggleRun,
                          ),
                        ),
                        const SizedBox(
                          width: 1,
                          child: ColoredBox(color: AppColors.divider),
                        ),
                        Expanded(
                          child: effect == null
                              ? const SizedBox.shrink()
                              : EffectDetailsPane(
                                  effect: effect,
                                  files: model.files,
                                  shell: shell,
                                  graphFile: graphFile,
                                  onOpenEffect: onOpenEffect,
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

/// The chevron and `Logs`, which fold the panel, and the copy shown with
/// its effects.
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
              child: Text.rich(
                TextSpan(
                  children: [
                    if (header.copy case final copy?) ...[
                      TextSpan(
                        text: copy,
                        style: AppText.logsEffects.copyWith(
                          color: AppColors.accentText,
                        ),
                      ),
                      const TextSpan(text: ' · '),
                    ],
                    TextSpan(text: header.effectsText),
                  ],
                ),
                style: AppText.logsEffects,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
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
