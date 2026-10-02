/// When a recent graph was opened, as its card on the start screen says it:
/// `Opened just now`, `Opened 5 minutes ago`, `Opened 2 hours ago`,
/// `Opened yesterday`, `Opened Sep 8`, `Opened Sep 8, 2025`.
///
/// Under a day ago counts minutes or hours; after that the local calendar
/// decides between yesterday and the date.
String openedAgo(DateTime openedAt, DateTime now) {
  final opened = openedAt.toLocal();
  final local = now.toLocal();
  final ago = local.difference(opened);
  if (ago.inMinutes < 1) return 'Opened just now';
  if (ago.inHours < 1) return 'Opened ${_count(ago.inMinutes, 'minute')} ago';
  if (ago.inDays < 1) return 'Opened ${_count(ago.inHours, 'hour')} ago';
  final day = DateTime(opened.year, opened.month, opened.day);
  if (day == DateTime(local.year, local.month, local.day - 1)) {
    return 'Opened yesterday';
  }
  final date = '${_months[opened.month - 1]} ${opened.day}';
  return opened.year == local.year
      ? 'Opened $date'
      : 'Opened $date, ${opened.year}';
}

String _count(int n, String unit) => n == 1 ? '1 $unit' : '$n ${unit}s';

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
