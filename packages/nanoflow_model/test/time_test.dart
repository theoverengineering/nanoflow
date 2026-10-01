import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:test/test.dart';

void main() {
  group('formatTime', () {
    test('writes UTC with three fractional digits and Z', () {
      expect(
        formatTime(DateTime.utc(2026, 9, 20, 14, 3, 11, 470)),
        '2026-09-20T14:03:11.470Z',
      );
    });

    test('pads milliseconds to three digits', () {
      expect(
        formatTime(DateTime.utc(2026, 9, 20, 14, 3, 11)),
        '2026-09-20T14:03:11.000Z',
      );
      expect(
        formatTime(DateTime.utc(2026, 9, 20, 14, 3, 11, 7)),
        '2026-09-20T14:03:11.007Z',
      );
    });

    test('keeps three digits when the time has microseconds', () {
      expect(
        formatTime(DateTime.utc(2026, 9, 20, 14, 3, 11, 470, 123)),
        '2026-09-20T14:03:11.470Z',
      );
    });

    test('truncates microseconds instead of rounding them', () {
      expect(
        formatTime(DateTime.utc(2026, 9, 20, 14, 3, 11, 470, 999)),
        '2026-09-20T14:03:11.470Z',
      );
    });

    test('converts a non-UTC time to UTC', () {
      final utc = DateTime.utc(2026, 9, 20, 14, 3, 11, 470);
      final local = utc.toLocal();

      expect(local.isUtc, isFalse);
      expect(formatTime(local), '2026-09-20T14:03:11.470Z');
    });
  });

  group('parseTime', () {
    test('returns a UTC DateTime', () {
      final time = parseTime('2026-09-20T14:03:11.470Z');

      expect(time.isUtc, isTrue);
      expect(time, DateTime.utc(2026, 9, 20, 14, 3, 11, 470));
    });

    test('round-trips what formatTime wrote', () {
      for (final text in [
        '2026-09-20T14:03:11.470Z',
        '2026-09-20T14:03:11.000Z',
        '2026-12-31T23:59:59.999Z',
        '2028-02-29T00:00:00.001Z',
      ]) {
        expect(formatTime(parseTime(text)), text);
      }
    });

    test('round-trips a time down to the millisecond', () {
      final time = DateTime.utc(2026, 9, 20, 14, 3, 11, 470, 123);

      expect(
        parseTime(formatTime(time)),
        DateTime.utc(2026, 9, 20, 14, 3, 11, 470),
      );
    });

    test('throws FormatException on input that is not a time', () {
      for (final text in ['', 'garbage', '2026-09-20', '14:03:11.470Z']) {
        expect(() => parseTime(text), throwsFormatException, reason: text);
      }
    });

    test(
      'throws FormatException on a time not written the way formatTime does',
      () {
        for (final text in [
          '2026-09-20T14:03:11Z', // no milliseconds
          '2026-09-20T14:03:11.4Z', // too few digits
          '2026-09-20T14:03:11.470123Z', // microseconds
          '2026-09-20T14:03:11.470', // no zone: would be read as local time
          '2026-09-20T14:03:11.470+00:00', // offset instead of Z
          '2026-09-20T16:03:11.470+02:00', // other zone
          '2026-09-20 14:03:11.470Z', // space instead of T
          ' 2026-09-20T14:03:11.470Z', // surrounding whitespace
          '2026-09-20T14:03:11.470Z\n',
        ]) {
          expect(() => parseTime(text), throwsFormatException, reason: text);
        }
      },
    );

    test('throws FormatException on dates that do not exist', () {
      for (final text in [
        '2026-02-30T14:03:11.470Z', // Dart would roll this over to March 2
        '2026-13-01T14:03:11.470Z',
        '2026-09-20T24:00:00.000Z',
        '2026-09-20T14:60:11.470Z',
      ]) {
        expect(() => parseTime(text), throwsFormatException, reason: text);
      }
    });
  });

  group('systemClock', () {
    test('is a Clock', () {
      final Clock clock = systemClock;

      expect(clock(), isA<DateTime>());
    });

    test('returns the current time in UTC', () {
      final before = DateTime.now().toUtc();
      final now = systemClock();
      final after = DateTime.now().toUtc();

      expect(now.isUtc, isTrue);
      expect(now.isBefore(before), isFalse);
      expect(now.isAfter(after), isFalse);
    });
  });
}
