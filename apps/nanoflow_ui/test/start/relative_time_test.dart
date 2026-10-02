import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/start/relative_time.dart';

void main() {
  // Local times: the label follows the local calendar.
  final now = DateTime(2026, 9, 21, 14, 30);
  String ago(Duration duration) => openedAgo(now.subtract(duration), now);

  test('under a minute ago is just now', () {
    expect(ago(Duration.zero), 'Opened just now');
    expect(ago(const Duration(seconds: 59)), 'Opened just now');
  });

  test('a time after now (the clock moved back) is just now', () {
    expect(ago(const Duration(minutes: -3)), 'Opened just now');
  });

  test('under an hour ago counts minutes', () {
    expect(ago(const Duration(minutes: 1)), 'Opened 1 minute ago');
    expect(
      ago(const Duration(minutes: 5, seconds: 40)),
      'Opened 5 minutes ago',
    );
    expect(ago(const Duration(minutes: 59)), 'Opened 59 minutes ago');
  });

  test('under a day ago counts hours, even across midnight', () {
    expect(ago(const Duration(hours: 1)), 'Opened 1 hour ago');
    expect(ago(const Duration(hours: 2, minutes: 50)), 'Opened 2 hours ago');
    expect(ago(const Duration(hours: 23, minutes: 59)), 'Opened 23 hours ago');
  });

  test('a day or more ago on the previous calendar day is yesterday', () {
    expect(openedAgo(DateTime(2026, 9, 20, 10), now), 'Opened yesterday');
    expect(
      openedAgo(DateTime(2025, 12, 31, 8), DateTime(2026, 1, 1, 12)),
      'Opened yesterday',
    );
  });

  test('earlier this year shows the day', () {
    expect(openedAgo(DateTime(2026, 9, 19, 23), now), 'Opened Sep 19');
    expect(openedAgo(DateTime(2026, 9, 8, 9), now), 'Opened Sep 8');
    expect(openedAgo(DateTime(2026, 1, 1), now), 'Opened Jan 1');
  });

  test('another year shows the year too', () {
    expect(openedAgo(DateTime(2025, 9, 8), now), 'Opened Sep 8, 2025');
    expect(
      openedAgo(DateTime(2025, 12, 30, 20), DateTime(2026, 1, 2, 10)),
      'Opened Dec 30, 2025',
    );
  });

  test('every month has its short English name', () {
    final endOfYear = DateTime(2026, 12, 31);
    expect(
      [
        for (var m = 1; m <= 12; m++)
          openedAgo(DateTime(2026, m, 8), endOfYear),
      ],
      [
        'Opened Jan 8',
        'Opened Feb 8',
        'Opened Mar 8',
        'Opened Apr 8',
        'Opened May 8',
        'Opened Jun 8',
        'Opened Jul 8',
        'Opened Aug 8',
        'Opened Sep 8',
        'Opened Oct 8',
        'Opened Nov 8',
        'Opened Dec 8',
      ],
    );
  });

  test('a UTC time is placed on the local calendar', () {
    final opened = now.subtract(const Duration(days: 1, hours: 2)).toUtc();
    expect(openedAgo(opened, now), 'Opened yesterday');
  });
}
