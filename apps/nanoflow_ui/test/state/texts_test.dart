import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/state/texts.dart';

void main() {
  test('an id is shortened to its first 4 characters', () {
    expect(shortId('a1b2c3d4-0000-4000-8000-000000000000'), 'a1b2');
    expect(shortId('ab'), 'ab');
  });

  group('a duration', () {
    Duration ms(int milliseconds) => Duration(milliseconds: milliseconds);

    test('under a second shows tenths: 0.4s', () {
      expect(formatDuration(ms(400)), '0.4s');
      expect(formatDuration(ms(999)), '0.9s');
      expect(formatDuration(Duration.zero), '0.0s');
    });

    test('under a minute shows seconds: 26s', () {
      expect(formatDuration(ms(1000)), '1s');
      expect(formatDuration(ms(26900)), '26s');
      expect(formatDuration(ms(59999)), '59s');
    });

    test('under an hour shows minutes and two-digit seconds: 2m 29s', () {
      expect(formatDuration(const Duration(minutes: 2, seconds: 29)), '2m 29s');
      expect(formatDuration(const Duration(minutes: 4, seconds: 2)), '4m 02s');
      expect(formatDuration(const Duration(minutes: 1)), '1m 00s');
    });

    test('of an hour or more shows hours and two-digit minutes: 1h 12m', () {
      expect(formatDuration(const Duration(hours: 1, minutes: 12)), '1h 12m');
      expect(
        formatDuration(const Duration(hours: 1, minutes: 6, seconds: 59)),
        '1h 06m',
      );
      expect(formatDuration(const Duration(hours: 26)), '26h 00m');
    });

    test('below zero, as a clock that went back makes it, shows 0.0s', () {
      expect(formatDuration(const Duration(seconds: -3)), '0.0s');
    });
  });

  group('elapsed time', () {
    test('keeps the seconds past an hour: 2h 54m 27s', () {
      expect(
        formatElapsed(const Duration(hours: 2, minutes: 54, seconds: 27)),
        '2h 54m 27s',
      );
      expect(
        formatElapsed(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1h 02m 03s',
      );
    });

    test('is a duration under an hour: 12m 26s, 42s', () {
      expect(
        formatElapsed(const Duration(minutes: 12, seconds: 26)),
        '12m 26s',
      );
      expect(formatElapsed(const Duration(seconds: 42)), '42s');
    });
  });

  test('a time of day is local HH:MM:SS', () {
    expect(clockTime(DateTime(2026, 9, 21, 9, 5, 3).toUtc()), '09:05:03');
  });

  group('a day and time', () {
    final now = DateTime(2026, 9, 21, 16);

    test('today is Today · 14:03:11', () {
      expect(
        dayAndTime(DateTime(2026, 9, 21, 14, 3, 11).toUtc(), now),
        'Today · 14:03:11',
      );
    });

    test('the day before is Yesterday · 19:12:55', () {
      expect(
        dayAndTime(DateTime(2026, 9, 20, 19, 12, 55).toUtc(), now),
        'Yesterday · 19:12:55',
      );
      expect(
        dayAndTime(DateTime(2026, 9, 30, 23, 59, 59), DateTime(2026, 10, 1)),
        'Yesterday · 23:59:59',
      );
    });

    test('earlier this year is the date: Sep 18 · 16:05:33', () {
      expect(
        dayAndTime(DateTime(2026, 9, 18, 16, 5, 33).toUtc(), now),
        'Sep 18 · 16:05:33',
      );
      expect(
        dayAndTime(DateTime(2026, 1, 2, 3, 4, 5), now),
        'Jan 2 · 03:04:05',
      );
    });

    test('another year adds the year: Sep 18, 2025 · 16:05:33', () {
      expect(
        dayAndTime(DateTime(2025, 9, 18, 16, 5, 33).toUtc(), now),
        'Sep 18, 2025 · 16:05:33',
      );
      expect(
        dayAndTime(DateTime(2025, 12, 31, 8), DateTime(2026, 1, 1, 9)),
        'Yesterday · 08:00:00',
      );
    });
  });

  test('a count names one thing in the singular: 1 run, 3 runs', () {
    expect(count(1, 'run'), '1 run');
    expect(count(3, 'run'), '3 runs');
    expect(count(0, 'step'), '0 steps');
  });
}
