import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../state/log_rows.dart' show EffectRow;
import '../../state/visits.dart' show StartOutcome;
import '../../theme.dart';
import '../../widgets/icons.dart';
import '../../widgets/spinner.dart';

/// An effect's timeline: the track, and on it the effect's bar from where it
/// started to where it ended or is now.
class EffectTrack extends StatelessWidget {
  const EffectTrack(this.row, {super.key});

  final EffectRow row;

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
      return Center(
        child: Container(
          key: EffectTrack.trackKey(row.effectId),
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
                child: EffectBar(
                  key: EffectTrack.barKey(row.effectId),
                  status: row.status,
                  striped: row.striped,
                  radius: length > _leastBar ? 3 : 1,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// An effect's bar in the color of its state; striped while it runs; only
/// outlined once it was interrupted: when it would have ended is not known.
class EffectBar extends StatelessWidget {
  const EffectBar({
    super.key,
    required this.status,
    required this.striped,
    required this.radius,
  });

  final StartOutcome status;
  final bool striped;
  final double radius;

  @override
  Widget build(BuildContext context) => status == StartOutcome.interrupted
      ? DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: status.color),
            borderRadius: BorderRadius.circular(radius),
          ),
        )
      : ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: striped
              ? const CustomPaint(painter: _StripesPainter())
              : ColoredBox(color: status.color),
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
