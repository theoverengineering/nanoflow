/// The sessions column and the session strip over the canvas
/// (docs/ui-spec.md «Сессии»). Pure: the time is passed in.
library;

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import 'session_feed.dart';
import 'texts.dart';
import 'texts.dart' as texts show shortId;

/// Where a session is (ui-spec «Сессии»).
enum SessionStatus {
  /// At least one run has not ended.
  running,

  /// Every run has ended, at least one with `run-failed`.
  failed,

  /// Every run has ended, none failed.
  finished,
}

/// A session's card in the sessions column and its strip over the canvas.
final class SessionSummary {
  SessionSummary._({
    required this.id,
    required this.startedAt,
    required this.status,
    required this.duration,
    required this.runs,
    required this.failedRuns,
    required this.firstLine,
  });

  final String id;

  String get shortId => texts.shortId(id);

  /// The first `run-started` of the session's runs, in UTC.
  final DateTime startedAt;

  final SessionStatus status;

  /// From [startedAt] to the end of the last run; for a running session, to
  /// now.
  final Duration duration;

  /// How many runs the session has.
  final int runs;

  /// How many of them failed.
  final int failedRuns;

  /// The day and time the session started: `Today · 14:03:11`.
  final String firstLine;

  /// `Running for 12m 26s`, `Failed in 6m 18s`, `Finished in 3m 04s`.
  String get statusText => switch (status) {
    SessionStatus.running => 'Running for ${formatDuration(duration)}',
    SessionStatus.failed => 'Failed in ${formatDuration(duration)}',
    SessionStatus.finished => 'Finished in ${formatDuration(duration)}',
  };

  /// `1 failed` next to the status of a running session with failed runs.
  String? get failedBadge => status == SessionStatus.running && failedRuns > 0
      ? '$failedRuns failed'
      : null;

  /// `1 run`, `3 runs`.
  String get runsText => count(runs, 'run');

  /// `started 14:03:11`, on the strip over the canvas.
  String get startedText => 'started ${clockTime(startedAt)}';

  /// `running 12m 26s`, `failed in 6m 18s`, `finished in 3m 04s`, on the
  /// strip over the canvas, to the second.
  String get stripStatus => switch (status) {
    SessionStatus.running => 'running ${formatElapsed(duration)}',
    SessionStatus.failed => 'failed in ${formatElapsed(duration)}',
    SessionStatus.finished => 'finished in ${formatElapsed(duration)}',
  };
}

/// The summary of [session] at [now]; `null` while none of its runs has a
/// `run-started`: a session has no start time before that.
SessionSummary? summarize(SessionData session, DateTime now) {
  final start = sessionStart(session);
  if (start == null) return null;
  final runs = session.runs.values;
  final ended = runs.every((run) => run.state.isEnded);
  final failed = runs.where((run) => run.state.status == RunStatus.failed);
  return SessionSummary._(
    id: session.id,
    startedAt: start,
    status: !ended
        ? SessionStatus.running
        : failed.isNotEmpty
        ? SessionStatus.failed
        : SessionStatus.finished,
    duration: (sessionEnd(session) ?? now).difference(start),
    runs: runs.length,
    failedRuns: failed.length,
    firstLine: dayAndTime(start, now),
  );
}

/// The first `run-started` of [session]'s runs; `null` before there is one.
DateTime? sessionStart(SessionData session) {
  DateTime? start;
  for (final run in session.runs.values) {
    final time = run.started?.time;
    if (time != null && (start == null || time.isBefore(start))) start = time;
  }
  return start;
}

/// When the last run of [session] ended; `null` while a run goes on.
DateTime? sessionEnd(SessionData session) {
  DateTime? end;
  for (final run in session.runs.values) {
    final time = run.state.finishedAt;
    if (time == null) return null;
    if (end == null || time.isAfter(end)) end = time;
  }
  return end;
}

/// What the sessions column says instead of sessions when the graph has
/// none.
const noRunsYet = 'No runs yet';

/// How to start a session of the YAML graph [graphFile]: sessions are read
/// from the `runs` directory next to it, where `nanoflow run` started from
/// its directory puts them.
String noRunsHint(String graphFile) =>
    "Start a session from the graph's directory: "
    'nanoflow run -- nanoflow-yaml ${p.basename(graphFile)}';

/// The summaries of [sessions] that have started, newest first.
List<SessionSummary> sessionSummaries(
  Iterable<SessionData> sessions,
  DateTime now,
) => [
  for (final session in sessionsNewestFirst(sessions)) summarize(session, now)!,
];

/// Those of [sessions] that have started, newest first (ui-spec «Сессии»).
List<SessionData> sessionsNewestFirst(Iterable<SessionData> sessions) {
  final started = [
    for (final session in sessions)
      if (sessionStart(session) case final start?) (session, start),
  ];
  started.sort((a, b) {
    final byTime = b.$2.compareTo(a.$2);
    return byTime != 0 ? byTime : a.$1.id.compareTo(b.$1.id);
  });
  return [for (final (session, _) in started) session];
}
