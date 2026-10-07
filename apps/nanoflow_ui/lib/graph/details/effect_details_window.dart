import 'dart:math' as math;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nanoflow_model/nanoflow_model.dart' show EffectNode;

import '../../platform/shell.dart';
import '../../state/clock.dart';
import '../../state/graph_model.dart';
import '../../state/visit_details.dart';
import '../../state/visits.dart';
import '../../theme.dart';
import '../../widgets/clickable.dart';
import '../../widgets/icons.dart';
import '../../widgets/spinner.dart';
import 'node_column.dart';
import 'output_column.dart';

/// The effect details window (docs/ui-spec.md «Окно деталей эффекта»; spec §9
/// «Окно эффекта»), over the whole graph screen, the dotted backdrop round it:
/// the effect [effectId] — or, without one, the effect node [node] alone.
///
/// The top bar has `Back to canvas`, the effect's icon, name and place, the
/// switcher `Visit 2 of 2` through every visit to its node among the effects
/// shown, the copy it is in, how it went, and close; Esc closes too. Under
/// it, the column of the effect — its place in the code and its facts — and
/// `Output`. An effect has no input. Showing another visit is [onVisit]: the
/// graph screen selects it. The window stays on its effect while the
/// selection follows a running session's new effects.
class EffectDetailsWindow extends StatefulWidget {
  const EffectDetailsWindow({
    super.key,
    required this.model,
    required this.clock,
    required this.shell,
    required this.graphFile,
    required this.effectId,
    this.node,
    required this.onVisit,
    required this.onClose,
  });

  final GraphModel model;
  final LiveClock clock;
  final Shell shell;

  /// The graph file: paths are shown from its directory.
  final String graphFile;

  /// The effect shown; `null` for the [node] alone.
  final String? effectId;

  /// The node double clicked: shown alone without an effect.
  final EffectNode? node;

  final ValueChanged<Visit> onVisit;
  final VoidCallback onClose;

  static const topBarKey = ValueKey('details top bar');
  static const backKey = ValueKey('details back');
  static const closeKey = ValueKey('details close');
  static const previousKey = ValueKey('previous visit');
  static const nextKey = ValueKey('next visit');
  static const copyKey = ValueKey('details copy');

  /// Round the window, the graph screen's dots show: 40 px at the sides, 36
  /// at the top and the bottom.
  static const margin = EdgeInsets.symmetric(horizontal: 40, vertical: 36);

  @override
  State<EffectDetailsWindow> createState() => _EffectDetailsWindowState();
}

class _EffectDetailsWindowState extends State<EffectDetailsWindow> {
  final _focus = FocusNode(debugLabel: 'effect details window');

  @override
  void initState() {
    super.initState();
    // Whatever had the keyboard, Esc is the window's now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    autofocus: true,
    onKeyEvent: _key,
    child: CustomPaint(
      painter: const _BackdropPainter(),
      child: Padding(
        padding: EffectDetailsWindow.margin,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.panel,
            border: Border.all(color: AppColors.controlBorder),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x8C000000),
                offset: Offset(0, 24),
                blurRadius: 60,
              ),
            ],
          ),
          // Inside the border, as CSS lays out a box's content.
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: ListenableBuilder(
                listenable: Listenable.merge([widget.model, widget.clock]),
                builder: (context, _) => _window(
                  widget.model.detailsOf(
                    widget.node,
                    widget.effectId,
                    widget.clock.now(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _window(VisitDetails details) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _TopBar(
        details: details,
        onVisit: widget.onVisit,
        onClose: widget.onClose,
      ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The mockup's node column, 520 of its 1358 inside the border;
            // the output takes the rest, the input's room too.
            final width = constraints.maxWidth;
            final effect = (width * 520 / 1358).clamp(0.0, 520.0);
            final files = widget.model.files;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: effect,
                  child: NodeColumn(
                    details: details,
                    files: files,
                    shell: widget.shell,
                    graphFile: widget.graphFile,
                  ),
                ),
                Expanded(
                  child: ColoredBox(
                    color: AppColors.backdrop,
                    child: OutputColumn(
                      details: details,
                      files: files,
                      shell: widget.shell,
                      graphFile: widget.graphFile,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ],
  );
}

/// `Back to canvas`, the effect, the visit switcher and the copy, how the
/// effect went, close.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.details,
    required this.onVisit,
    required this.onClose,
  });

  final VisitDetails details;
  final ValueChanged<Visit> onVisit;
  final VoidCallback onClose;

  /// The widest the effect's name and place get before they are cut: a
  /// quarter of the bar, and no more than this.
  static const _nameWidth = 320.0;

  /// Shows [visit] on a click; nothing without one.
  VoidCallback? _show(Visit? visit) =>
      visit == null ? null : () => onVisit(visit);

  @override
  Widget build(BuildContext context) => Container(
    key: EffectDetailsWindow.topBarKey,
    height: 56,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.topBarBorder)),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) => _row(
        context,
        nameWidth: math.min(constraints.maxWidth / 4, _nameWidth),
      ),
    ),
  );

  Widget _row(BuildContext context, {required double nameWidth}) {
    final visit = details.visit;
    final place = details.place;
    final result = details.result;
    return Row(
      spacing: 14,
      children: [
        Clickable(
          key: EffectDetailsWindow.backKey,
          onTap: onClose,
          child: _Button(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 7,
              children: [
                const ChevronIcon(size: 12, color: AppColors.textSecondary),
                Text('Back to canvas', style: AppText.button),
              ],
            ),
          ),
        ),
        const SizedBox(
          width: 1,
          height: 24,
          child: ColoredBox(color: AppColors.panelBorder),
        ),
        _NodeBadge(status: result?.status),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: nameWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 1,
            children: [
              Text(
                details.name,
                style: AppText.windowNode,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (place != null)
                Text(
                  place,
                  style: AppText.windowPlace,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        const Spacer(),
        if (visit != null) ...[
          _VisitSwitcher(
            number: details.index! + 1,
            count: details.visits.length,
            onPrevious: _show(details.previous),
            onNext: _show(details.next),
          ),
          if (details.copy case final copy?)
            Text(
              copy,
              key: EffectDetailsWindow.copyKey,
              style: AppText.windowCopy,
            ),
        ],
        const Spacer(),
        if (result != null) _ResultChip(result),
        Clickable(
          key: EffectDetailsWindow.closeKey,
          onTap: onClose,
          child: const _Button(
            width: 30,
            height: 30,
            radius: 7,
            child: CloseIcon(size: 11, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// A button's box: `Back to canvas`, close.
class _Button extends StatelessWidget {
  const _Button({
    required this.child,
    this.padding,
    this.width,
    this.height,
    this.radius = 7,
  });

  final Widget child;
  final EdgeInsets? padding;
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    padding: padding,
    alignment: width == null ? null : Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.control,
      border: Border.all(color: AppColors.controlBorder),
      borderRadius: BorderRadius.circular(radius),
    ),
    child: child,
  );
}

/// An effect's icon in a tile framed in the color of how the effect went.
class _NodeBadge extends StatelessWidget {
  const _NodeBadge({required this.status});

  /// `null` for the node's description alone.
  final StartOutcome? status;

  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 32,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.tile,
      border: Border.all(
        color: status?.color ?? AppColors.tileBorder,
        width: 1.5,
      ),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const EffectIcon(
      size: 18,
      color: AppColors.textAreaText,
      strokeWidth: 2,
    ),
  );
}

/// `‹ Visit 2 of 2 ›`: a chevron without a visit that way is dim and does
/// nothing.
class _VisitSwitcher extends StatelessWidget {
  const _VisitSwitcher({
    required this.number,
    required this.count,
    required this.onPrevious,
    required this.onNext,
  });

  final int number;
  final int count;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  Widget _arrow(Key key, VoidCallback? onTap, {required bool right}) {
    final icon = SizedBox(
      key: key,
      width: 26,
      height: 26,
      child: Center(
        child: ChevronIcon(
          size: 12,
          right: right,
          color: onTap == null ? AppColors.separator : AppColors.textSecondary,
        ),
      ),
    );
    return onTap == null ? icon : Clickable(onTap: onTap, child: icon);
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: AppColors.card,
      border: Border.all(color: AppColors.panelBorder),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        _arrow(EffectDetailsWindow.previousKey, onPrevious, right: false),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text.rich(
            TextSpan(
              text: 'Visit ',
              children: [
                TextSpan(
                  text: '$number',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: ' of $count'),
              ],
            ),
            style: AppText.visitText,
          ),
        ),
        _arrow(EffectDetailsWindow.nextKey, onNext, right: true),
      ],
    ),
  );
}

/// `finished · 4m 02s` in green; failed in red, running in amber,
/// `interrupted` muted.
class _ResultChip extends StatelessWidget {
  const _ResultChip(this.result);

  final EffectResult result;

  @override
  Widget build(BuildContext context) {
    final (surface, border, text) = switch (result.status) {
      StartOutcome.finished => (
        AppColors.finishedSurface,
        AppColors.finishedBorder,
        AppColors.finishedText,
      ),
      StartOutcome.running => (
        AppColors.runningSurface,
        AppColors.runningBorder,
        AppColors.running,
      ),
      StartOutcome.interrupted => (
        AppColors.control,
        AppColors.controlBorder,
        AppColors.interrupted,
      ),
      StartOutcome.failed => (
        AppColors.dangerSurface,
        AppColors.dangerBorder,
        AppColors.dangerText,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 7,
        children: [
          switch (result.status) {
            StartOutcome.finished => const CheckIcon(
              size: 10,
              color: AppColors.finished,
              strokeWidth: 1.9,
            ),
            StartOutcome.running => const Spinner(size: 10, strokeWidth: 2.6),
            StartOutcome.interrupted => const PauseIcon(
              size: 10,
              color: AppColors.interrupted,
              strokeWidth: 1.9,
            ),
            StartOutcome.failed => const CloseIcon(
              size: 9,
              color: AppColors.failed,
            ),
          },
          Text(result.text, style: AppText.resultChip.copyWith(color: text)),
        ],
      ),
    );
  }
}

/// The window's backdrop: the canvas's dots, dimmed, 22 px apart.
class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  static const _cell = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.backdrop);
    // A dot in the middle of each cell, as the mockup's CSS grid has them.
    final dots = [
      for (var x = _cell / 2; x < size.width; x += _cell)
        for (var y = _cell / 2; y < size.height; y += _cell) Offset(x, y),
    ];
    canvas.drawPoints(
      PointMode.points,
      dots,
      Paint()
        ..color = AppColors.backdropDot
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => false;
}
