import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/state/clock.dart';

void main() {
  test('now is the time it is given', () {
    final clock = LiveClock(now: () => DateTime.utc(2026, 9, 21, 12));
    expect(clock.now(), DateTime.utc(2026, 9, 21, 12));
  });

  test('ticks every second while someone listens, and only then', () {
    fakeAsync((async) {
      final clock = LiveClock(now: () => async.getClock(DateTime(2026)).now());
      var ticks = 0;
      void tick() => ticks++;

      async.elapse(const Duration(seconds: 3));
      expect(async.pendingTimers, isEmpty);

      clock.addListener(tick);
      async.elapse(const Duration(milliseconds: 2500));
      expect(ticks, 2);

      clock.removeListener(tick);
      expect(async.pendingTimers, isEmpty);
      async.elapse(const Duration(seconds: 3));
      expect(ticks, 2);
      clock.dispose();
    });
  });

  test('stops ticking when disposed', () {
    fakeAsync((async) {
      LiveClock()
        ..addListener(() {})
        ..dispose();
      expect(async.pendingTimers, isEmpty);
    });
  });
}
