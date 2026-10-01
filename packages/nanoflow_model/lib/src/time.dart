/// A source of the current time. The engine takes one so tests can fix it.
typedef Clock = DateTime Function();

/// The wall clock, in UTC.
DateTime systemClock() => DateTime.now().toUtc();

/// Formats [t] as UTC ISO-8601 with exactly three fractional digits and `Z`:
/// `2026-09-20T14:03:11.470Z`.
///
/// Microseconds are dropped, never written.
String formatTime(DateTime t) {
  final utc = t.toUtc();
  // Rebuilt without microseconds, so `toIso8601String` prints exactly three
  // fractional digits.
  return DateTime.utc(
    utc.year,
    utc.month,
    utc.day,
    utc.hour,
    utc.minute,
    utc.second,
    utc.millisecond,
  ).toIso8601String();
}

/// Parses a time written by [formatTime] into a UTC [DateTime].
///
/// Accepts only that exact form (`2026-09-20T14:03:11.470Z`): a time without
/// a zone would otherwise be read as local, and a date that does not exist,
/// like February 30, would be silently rolled over. Throws [FormatException]
/// on anything else.
DateTime parseTime(String s) {
  final time = DateTime.parse(s).toUtc();
  if (formatTime(time) != s) {
    throw FormatException(
      'Expected a UTC time like 2026-09-20T14:03:11.470Z',
      s,
    );
  }
  return time;
}
