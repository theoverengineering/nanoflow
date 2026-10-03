import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../state/log_rows.dart' show StepRow;
import '../../state/visits.dart' show StartOutcome;
import '../../theme.dart';
import '../../widgets/icons.dart';
import '../../widgets/spinner.dart';

/// A step's timeline: the track, and on it the step's bar from where it
/// started to where it ended or is now.
class StepTrack extends StatelessWidget {
  const StepTrack(this.row, {super.key});

  final StepRow row;

  static Key trackKey(String stepId) => ValueKey(('step track', stepId));
  static Key barKey(String stepId) => ValueKey(('step bar', stepId));

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
          key: StepTrack.trackKey(row.stepId),
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
                child: StepBar(
                  key: StepTrack.barKey(row.stepId),
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

/// A step's bar in the color of its state; striped while it runs; only
/// outlined once it was interrupted: when it would have ended is not known.
class StepBar extends StatelessWidget {
  const StepBar({
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
    final step = _period * math.sqrt2;
    final stripe = step / 2;
    final h = size.height;
    final paint = Paint()..color = AppColors.running;
    for (var x = -h; x < size.width; x += step) {
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

/// A step's sign: a green check finished, the turning sign running, a red
/// cross failed, a grey pause interrupted.
class StepIcon extends StatelessWidget {
  const StepIcon(this.status, {super.key});

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
      painter: _StepSignPainter(status),
    ),
  };
}

/// The mockup's check, 10 units; a cross of the same weight.
class _StepSignPainter extends CustomPainter {
  const _StepSignPainter(this.status);

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
  bool shouldRepaint(_StepSignPainter old) => old.status != status;
}
