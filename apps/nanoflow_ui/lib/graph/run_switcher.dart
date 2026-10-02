import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../state/runs.dart';
import '../theme.dart';
import '../widgets/clickable.dart';
import '../widgets/dot.dart';

/// The run switcher on the right of the session bar (docs/ui-spec.md
/// «Холст»): `Run` and the session's runs in the order they were created,
/// each by its short id with the sign of its state, a run that split with
/// `split` too; the selected run is filled with the accent. A run whose log
/// was read incompletely is marked [logReadIncompletely], why in a tooltip.
/// A click on a run selects it.
///
/// Too many runs to fit scroll sideways, by the mouse wheel too; the
/// selected run is scrolled into view whenever another is selected.
class RunSwitcher extends StatefulWidget {
  const RunSwitcher({
    super.key,
    required this.runs,
    required this.selected,
    required this.onSelect,
  });

  /// The runs, in the order they were created.
  final List<RunChip> runs;

  /// The selected run's id; `null` when none is.
  final String? selected;

  final ValueChanged<String> onSelect;

  /// The key of the run [runId]'s pill.
  static Key pillKey(String runId) => ValueKey(('run', runId));

  @override
  State<RunSwitcher> createState() => _RunSwitcherState();
}

class _RunSwitcherState extends State<RunSwitcher> {
  final _scroll = ScrollController();
  final _selectedPill = GlobalKey();

  @override
  void initState() {
    super.initState();
    _revealSelected(animate: false);
  }

  @override
  void didUpdateWidget(RunSwitcher old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) _revealSelected(animate: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls the runs, once they are laid out, just enough that the
  /// selected one is in view.
  void _revealSelected({required bool animate}) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final pill = _selectedPill.currentContext?.findRenderObject();
        if (!mounted || pill is! RenderBox || !_scroll.hasClients) return;
        final viewport = RenderAbstractViewport.of(pill);
        final position = _scroll.position;
        // The least and the most the runs can be scrolled to show it whole.
        final least = viewport.getOffsetToReveal(pill, 1).offset;
        final most = viewport.getOffsetToReveal(pill, 0).offset;
        final target = position.pixels
            .clamp(least, most)
            .clamp(position.minScrollExtent, position.maxScrollExtent);
        if (target == position.pixels) return;
        if (animate) {
          unawaited(
            position.animateTo(
              target,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
            ),
          );
        } else {
          position.jumpTo(target);
        }
      });

  /// The mouse wheel turned over the runs scrolls them sideways.
  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    final position = _scroll.position;
    final delta = event.scrollDelta.dy;
    if (delta == 0 || position.maxScrollExtent == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      position.jumpTo(
        (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => Container(
    height: 34,
    padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
    decoration: BoxDecoration(
      color: AppColors.panel,
      border: Border.all(color: AppColors.panelBorder),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Run', style: AppText.barLabel),
        const SizedBox(width: 8),
        Flexible(
          child: Listener(
            onPointerSignal: _wheel,
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 4,
                children: [
                  for (final run in widget.runs)
                    _RunPill(
                      run,
                      key: run.runId == widget.selected ? _selectedPill : null,
                      selected: run.runId == widget.selected,
                      onTap: () => widget.onSelect(run.runId),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// A run on the switcher: its sign, short id (the full one in a tooltip),
/// `split`, the [logReadIncompletely] mark.
class _RunPill extends StatelessWidget {
  const _RunPill(
    this.run, {
    super.key,
    required this.selected,
    required this.onTap,
  });

  final RunChip run;
  final bool selected;
  final VoidCallback onTap;

  /// How many of a run's problems its mark's tooltip lists.
  static const _problemsShown = 5;

  @override
  Widget build(BuildContext context) {
    final quiet =
        run.phase == RunPhase.split || run.phase == RunPhase.notStarted;
    final color = selected
        ? AppColors.onAccent
        : quiet
        ? AppColors.textMuted
        : AppColors.textSecondary;
    final word = run.word;
    return Clickable.hover(
      onTap: onTap,
      builder: (context, hovered) => Container(
        key: RunSwitcher.pillKey(run.runId),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent
              : hovered
              ? AppColors.control
              : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            RunSign(run.phase, onAccent: selected),
            Tooltip(
              message: run.runId,
              child: Text(
                run.shortId,
                style: AppText.runId.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w500 : null,
                ),
              ),
            ),
            if (word != null)
              Text(
                word,
                style: AppText.runWord.copyWith(
                  color: selected ? AppColors.onAccent : AppColors.textFaint,
                ),
              ),
            if (run.incomplete)
              Tooltip(message: _why(run.problems), child: const _Incomplete()),
          ],
        ),
      ),
    );
  }

  static String _why(List<String> problems) => [
    logReadIncompletely,
    ...problems.take(_problemsShown),
    if (problems.length > _problemsShown)
      'and ${problems.length - _problemsShown} more',
  ].join('\n');
}

/// The sign of a run's state: a hollow ring not started, an amber dot
/// running, a green check finished, a red cross failed, a fork split. On
/// the accent the quiet ones are white.
class RunSign extends StatelessWidget {
  const RunSign(this.phase, {super.key, this.onAccent = false});

  final RunPhase phase;
  final bool onAccent;

  @override
  Widget build(BuildContext context) => switch (phase) {
    RunPhase.running => const Dot(AppColors.running),
    RunPhase.finished => _sign(10, AppColors.finished),
    RunPhase.failed => _sign(10, AppColors.failed),
    RunPhase.split => _sign(
      11,
      onAccent ? AppColors.onAccent : AppColors.textMuted,
    ),
    RunPhase.notStarted => _sign(
      7,
      onAccent ? AppColors.onAccent : AppColors.textFaint,
    ),
  };

  Widget _sign(double size, Color color) =>
      CustomPaint(size: Size.square(size), painter: _SignPainter(phase, color));
}

/// The signs of [RunSign] but the dot: the mockup's SVG, 12 units for a
/// fork, 10 for the rest.
class _SignPainter extends CustomPainter {
  _SignPainter(this.phase, this.color);

  final RunPhase phase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (phase) {
      case RunPhase.notStarted:
        canvas.drawCircle(
          size.center(Offset.zero),
          size.width / 2 - 0.7,
          stroke..strokeWidth = 1.4,
        );
      case RunPhase.finished:
        canvas
          ..scale(size.width / 10)
          ..drawPath(
            Path()
              ..moveTo(1.4, 5.2)
              ..lineTo(3.8, 7.6)
              ..lineTo(8.6, 2.6),
            stroke..strokeWidth = 1.8,
          );
      case RunPhase.failed:
        canvas
          ..scale(size.width / 10)
          ..drawPath(
            Path()
              ..moveTo(2.4, 2.4)
              ..lineTo(7.6, 7.6)
              ..moveTo(7.6, 2.4)
              ..lineTo(2.4, 7.6),
            stroke..strokeWidth = 1.8,
          );
      case RunPhase.split:
        canvas
          ..scale(size.width / 12)
          ..drawPath(
            Path()
              ..moveTo(6, 1.5)
              ..lineTo(6, 5.1)
              ..moveTo(6, 5.1)
              ..lineTo(2.6, 8)
              ..lineTo(2.6, 10.5)
              ..moveTo(6, 5.1)
              ..lineTo(9.4, 8)
              ..lineTo(9.4, 10.5),
            stroke..strokeWidth = 1.4,
          );
      case RunPhase.running:
        return;
    }
  }

  @override
  bool shouldRepaint(_SignPainter old) =>
      old.phase != phase || old.color != color;
}

/// The [logReadIncompletely] mark: an amber triangle with `!`.
class _Incomplete extends StatelessWidget {
  const _Incomplete();

  @override
  Widget build(BuildContext context) => Semantics(
    label: logReadIncompletely,
    child: CustomPaint(
      size: const Size.square(12),
      painter: _IncompletePainter(),
    ),
  );
}

class _IncompletePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 12);
    final stroke = Paint()
      ..color = AppColors.running
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(
        Path()
          ..moveTo(6, 1.5)
          ..lineTo(11, 10.5)
          ..lineTo(1, 10.5)
          ..close(),
        stroke,
      )
      ..drawLine(const Offset(6, 5), const Offset(6, 7.2), stroke)
      ..drawCircle(
        const Offset(6, 9),
        0.75,
        Paint()..color = AppColors.running,
      );
  }

  @override
  bool shouldRepaint(_IncompletePainter old) => false;
}
