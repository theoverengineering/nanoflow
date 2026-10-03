import 'json_fields.dart';
import 'time.dart';

/// The process that owns a session: the one that holds its lock and writes
/// its journal. Kept in the session's `.owner.lock`.
///
/// A pid alone is not enough: the OS gives the number of a process that is
/// gone to another one. The pair of the pid and the time the process started
/// is what names it.
final class Owner {
  const Owner({required this.pid, required this.started});

  /// Reads an owner from its JSON form.
  ///
  /// Throws a [FormatException] whose message starts with the field that is
  /// missing or of the wrong kind; a `started` that [parseTime] rejects is
  /// one.
  factory Owner.fromJson(Map<String, Object?> json) => Owner(
    pid: readInt(json, 'pid'),
    started: readTimeOrNull(json, 'started'),
  );

  /// The process id.
  final int pid;

  /// When the process started, by the OS, in UTC to the millisecond (the form
  /// a `Processes` adapter gives and [fromJson] reads); `null` when the
  /// adapter does not know it.
  final DateTime? started;

  /// The JSON form: `pid`, then `started` in the time format of events.
  Map<String, Object?> toJson() => {'pid': pid, 'started': _startedText};

  /// [started] as it is written.
  String? get _startedText {
    final time = started;
    return time == null ? null : formatTime(time);
  }

  // Compared as written, so an owner equals the one read back from its JSON
  // form whatever the zone or the microseconds of its start time.
  @override
  bool operator ==(Object other) =>
      other is Owner && other.pid == pid && other._startedText == _startedText;

  @override
  int get hashCode => Object.hash(pid, _startedText);

  @override
  String toString() => 'Owner(pid: $pid, started: $_startedText)';
}
