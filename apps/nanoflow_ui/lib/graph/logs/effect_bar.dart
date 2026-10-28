import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../state/log_rows.dart' show BarPart, RunRow, TimedRow;
import '../../state/visits.dart' show StartOutcome;
import '../../theme.dart';
import '../../widgets/icons.dart';
import '../../widgets/spinner.dart';

/// An effect's timeline, or a run's: the track, and on it the bar from where it
/// started to where it ended or is now; a run's made of its effects' bars.
class EffectTrack extends StatelessWidget {
  const EffectTrack(this.row, {super.key});

  final TimedRow row;

  static Key trackKey(String effectId) => ValueKey(('effect track', effectId));
  static Key barKey(String effectId) => ValueKey(('effect bar', effectId));

  /// Shorter than this, a bar is this long.
  static const _leastBar = 2.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final length = math.max(_leastBar, (row.barEnd - row.barStart) * width);
      final left = math.min(row.barStart * width, width - length);
      final key = EffectTrack.barKey(row.barId);
      return Center(
        child: Container(
          key: EffectTrack.trackKey(row.barId),
          height: 6,
          decoration: BoxDecoration(
            color: AppColors.divider,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Stack(
            children: [
              Positioned(
                left: left,
                width: length,
                top: 0,
                bottom: 0,
                child: switch (row) {
                  RunRow(:final parts) => _RunBar(
                    key: key,
                    parts: parts,
                    left: left,
                    width: width,
                  ),
                  _ => EffectBar(
                    key: key,
                    status: row.status,
                    striped: row.striped,
                    radius: length > _leastBar ? 3 : 1,
                  ),
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// A run's bar: its effects' bars, square, each from where the effect started
/// to where it ended, every other one [EffectBar.shaded].
class _RunBar extends StatelessWidget {
  const _RunBar({
    super.key,
    required this.parts,
    required this.left,
    required this.width,
  });

  final List<BarPart> parts;

  /// Where the run's bar begins on the track, and how wide the track is.
  final double left;
  final double width;

  /// Shorter than this, an effect's bar in a run is this long.
  static const _leastPart = 1.0;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      for (final (i, part) in parts.indexed)
        Positioned(
          left: part.start * width - left,
          width: math.max(_leastPart, (part.end - part.start) * width),
          top: 0,
          bottom: 0,
          child: EffectBar(
            status: part.status,
            striped: part.status == StartOutcome.running,
            shaded: i.isOdd,
            radius: 0,
          ),
        ),
    ],
  );
}

/// An effect's bar in the color of its state; striped while it runs; only
/// outlined once it was interrupted: when it would have ended is not known.
class EffectBar extends StatelessWidget {
  const EffectBar({
    super.key,
    required this.status,
    required this.striped,
    this.shaded = false,
    required this.radius,
  });

  final StartOutcome status;
  final bool striped;

  /// Whether it is in a darker shade of its color, as every other effect's
  /// bar in a run's is, to tell them apart; not striped.
  final bool shaded;

  final double radius;

  /// How far toward the panel a shaded bar's color is.
  static const _shade = 0.4;

  Color get _color => shaded
      ? Color.lerp(status.color, AppColors.panel, _shade)!
      : status.color;

  @override
  Widget build(BuildContext context) => status == StartOutcome.interrupted
      ? DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: _color),
            borderRadius: BorderRadius.circular(radius),
          ),
        )
      : ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: striped
              ? const CustomPaint(painter: _StripesPainter())
              : ColoredBox(color: _color),
        );
}

/// The mockup's `repeating-linear-gradient(135deg, #F2A93B 0 4px, #C98526
/// 4px 8px)`: stripes rising to the right, 8 px apart across them.
class _StripesPainter extends CustomPainter {
  const _StripesPainter();

  static const _period = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = AppColors.runningStripe,
    );
    // Along the bar, a period and a stripe are √2 times as long.
    final effect = _period * math.sqrt2;
    final stripe = effect / 2;
    final h = size.height;
    final paint = Paint()..color = AppColors.running;
    for (var x = -h; x < size.width; x += effect) {
      canvas.drawPath(
        Path()
          ..moveTo(x, h)
          ..lineTo(x + h, 0)
          ..lineTo(x + h + stripe, 0)
          ..lineTo(x + stripe, h)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StripesPainter old) => false;
}

/// An effect's sign: a green check finished, the turning sign running, a red
/// cross failed, a grey pause interrupted.
class EffectIcon extends StatelessWidget {
  const EffectIcon(this.status, {super.key});

  final StartOutcome status;

  /// How wide and tall it is.
  static const size = 14.0;

  @override
  Widget build(BuildContext context) => switch (status) {
    StartOutcome.running => const Spinner(size: size, strokeWidth: 2.4),
    StartOutcome.interrupted => const PauseIcon(
      size: size,
      color: AppColors.interrupted,
    ),
    StartOutcome.finished || StartOutcome.failed => CustomPaint(
      size: const Size.square(size),
      painter: _EffectSignPainter(status),
    ),
  };
}

/// The mockup's check, 10 units; a cross of the same weight.
class _EffectSignPainter extends CustomPainter {
  const _EffectSignPainter(this.status);

  final StartOutcome status;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 10);
    final stroke = Paint()
      ..color = status.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      status == StartOutcome.failed
          ? (Path()
              ..moveTo(2.6, 2.6)
              ..lineTo(7.4, 7.4)
              ..moveTo(7.4, 2.6)
              ..lineTo(2.6, 7.4))
          : (Path()
              ..moveTo(1.6, 5.2)
              ..lineTo(3.8, 7.4)
              ..lineTo(8.4, 2.8)),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_EffectSignPainter old) => old.status != status;
}
