/// How times, durations, ids and counts read in the app (docs/ui-spec.md,
/// the mockups in docs/design/): English, local time.
library;

/// The first 4 characters of [id]: ids are shown shortened, the full one in
/// a tooltip.
String shortId(String id) => id.length <= 4 ? id : id.substring(0, 4);

/// [d] as the app shows how long something took or has been going: `0.4s`
/// under a second, `26s` under a minute, `2m 29s` under an hour, `1h 12m`
/// from an hour on. A duration below zero reads as zero.
String formatDuration(Duration d) {
  final ms = d.isNegative ? 0 : d.inMilliseconds;
  if (ms < 1000) return '0.${ms ~/ 100}s';
  final seconds = ms ~/ 1000;
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) return '${seconds ~/ 60}m ${_two(seconds % 60)}s';
  return '${seconds ~/ 3600}h ${_two(seconds ~/ 60 % 60)}m';
}

/// [d] to the second, as the session strip shows it: `42s`, `12m 26s`,
/// `2h 54m 27s`.
String formatElapsed(Duration d) {
  final seconds = d.isNegative ? 0 : d.inSeconds;
  if (seconds < 3600) {
    return seconds < 60 ? '${seconds}s' : formatDuration(d);
  }
  return '${seconds ~/ 3600}h ${_two(seconds ~/ 60 % 60)}m '
      '${_two(seconds % 60)}s';
}

/// The local time of day of [t]: `14:03:11`.
String clockTime(DateTime t) {
  final local = t.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)}';
}

/// The local time of day of [t] to the millisecond: `14:09:20.118`.
String clockTimeMillis(DateTime t) =>
    '${clockTime(t)}.${t.millisecond.toString().padLeft(3, '0')}';

/// The local day and time of [t] as seen at [now]: `Today · 14:03:11`,
/// `Yesterday · 19:12:55`, `Sep 18 · 16:05:33`, and for another year
/// `Sep 18, 2025 · 16:05:33`.
String dayAndTime(DateTime t, DateTime now) {
  final local = t.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final nowLocal = now.toLocal();
  final today = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
  // Calendar days, not 24-hour spans: a DST change makes a day 23 or 25 h.
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  final String date;
  if (day == today) {
    date = 'Today';
  } else if (day == yesterday) {
    date = 'Yesterday';
  } else {
    final month = _months[local.month - 1];
    date = local.year == today.year
        ? '$month ${local.day}'
        : '$month ${local.day}, ${local.year}';
  }
  return '$date · ${clockTime(local)}';
}

/// [n] with its thousands apart: `1,500`.
String thousands(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

/// [n] [noun]s: `1 run`, `3 runs`.
String count(int n, String noun) => n == 1 ? '1 $noun' : '$n ${noun}s';

String _two(int n) => n.toString().padLeft(2, '0');

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
