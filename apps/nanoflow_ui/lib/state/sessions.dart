/// The sessions column and the session strip over the canvas
/// (docs/ui-spec.md «Сессии»). Pure: the time is passed in.
library;

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import 'freshness.dart' show CodeCheck;
import 'project_dir.dart';
import 'session_feed.dart';
import 'texts.dart';
import 'texts.dart' as texts show shortId;

/// A session's card in the sessions column and its strip over the canvas.
final class SessionSummary {
  SessionSummary._({
    required this.id,
    required this.startedAt,
    required this.status,
    required this.interrupted,
    required this.duration,
    required this.effects,
    required this.failedEffects,
    required this.firstLine,
    required this.code,
    required this.changedOnResume,
    required this.from,
    required List<String> problems,
  }) : problems = List.unmodifiable(problems);

  final String id;

  String get shortId => texts.shortId(id);

  /// The session's `session-started`, in UTC.
  final DateTime startedAt;

  /// As its last event tells: running until `session-finished` or
  /// `session-failed`.
  final SessionStatus status;

  /// Whether the process that ran the session is gone though its journal
  /// has not ended (`SessionData.interrupted`): [status] is running, but it
  /// shows `Interrupted`.
  final bool interrupted;

  /// From [startedAt] to the session's last event; for a running session,
  /// to now — but for an [interrupted] one, to its last event.
  final Duration duration;

  /// How many effects the session has started.
  final int effects;

  /// How many of them failed the last time they ran.
  final int failedEffects;

  /// The day and time the session started: `Today · 14:03:11`.
  final String firstLine;

  /// How the code the session ran on stands against its graph; `null`
  /// while that is not known.
  final CodeCheck? code;

  /// Whether a resume of the session ran on code other than the code it
  /// started on (decision 7): its effects before that ran on other code. Both
  /// hashes must be known.
  final bool changedOnResume;

  /// [resumedOnChangedCode] on the card and the session bar when the
  /// session [changedOnResume]; `null` when not.
  String? get resumedNote => changedOnResume ? resumedOnChangedCode : null;

  /// The workflow of a parent's session — of a workflow that calls the
  /// called graph opened (open-as-graph design §4); `null` for any other
  /// session.
  final String? from;

  /// `from chain` on the card of a parent's session; `null` for any other.
  String? get fromText => from == null ? null : 'from $from';

  /// Why the session's journal was read incompletely
  /// (`SessionData.problems`); empty when it was read whole.
  final List<String> problems;

  /// Whether the session is marked [logReadIncompletely].
  bool get incomplete => problems.isNotEmpty;

  /// The tooltip of the [logReadIncompletely] mark: the mark, then the
  /// first [problemsShown] problems and how many more there are; `null`
  /// without problems.
  String? get incompleteWhy => incomplete
      ? [
          logReadIncompletely,
          ...problems.take(problemsShown),
          if (problems.length > problemsShown)
            'and ${problems.length - problemsShown} more',
        ].join('\n')
      : null;

  /// `other code` for a session that ran on code its graph was not read
  /// from; `not checked` for one that recorded no hash of its code.
  String? get codeNote => switch (code) {
    CodeCheck.otherCode => 'other code',
    CodeCheck.notChecked => 'not checked',
    CodeCheck.matches || null => null,
  };

  /// `Running for 12m 26s`, `Interrupted after 3m 20s`, `Failed in 6m 18s`,
  /// `Finished in 3m 04s`.
  String get statusText => switch (status) {
    SessionStatus.running when interrupted =>
      'Interrupted after ${formatDuration(duration)}',
    SessionStatus.running => 'Running for ${formatDuration(duration)}',
    SessionStatus.failed => 'Failed in ${formatDuration(duration)}',
    SessionStatus.finished => 'Finished in ${formatDuration(duration)}',
  };

  /// The tooltip of the status: [interruptedWhy] for an [interrupted]
  /// session; `null` for any other.
  String? get statusWhy => interrupted ? interruptedWhy : null;

  /// `1 failed` under the status of a running session with failed effects:
  /// the workflow caught what they threw, or has not yet.
  String? get failedBadge =>
      status == SessionStatus.running && failedEffects > 0
      ? '$failedEffects failed'
      : null;

  /// `1 effect`, `8 effects`.
  String get effectsText => count(effects, 'effect');

  /// `started 14:03:11`, on the strip over the canvas.
  String get startedText => 'started ${clockTime(startedAt)}';

  /// `running 12m 26s`, `interrupted after 3m 20s`, `failed in 6m 18s`,
  /// `finished in 3m 04s`, on the strip over the canvas, to the second.
  String get stripStatus => switch (status) {
    SessionStatus.running when interrupted =>
      'interrupted after ${formatElapsed(duration)}',
    SessionStatus.running => 'running ${formatElapsed(duration)}',
    SessionStatus.failed => 'failed in ${formatElapsed(duration)}',
    SessionStatus.finished => 'finished in ${formatElapsed(duration)}',
  };
}

/// The summary of [session] at [now], [code] the check of its code, [from]
/// the workflow of a parent's session (`SessionSummary.from`); `null` while
/// its `session-started` has not been read: a session has no start time
/// before that.
SessionSummary? summarize(
  SessionData session,
  DateTime now, {
  CodeCheck? code,
  String? from,
}) {
  final state = session.state;
  final start = state.startedAt;
  if (start == null) return null;
  return SessionSummary._(
    id: session.id,
    startedAt: start,
    status: state.status,
    interrupted: session.interrupted,
    duration: (state.finishedAt ?? session.timeAt(now)).difference(start),
    effects: state.effects.length,
    failedEffects: state.effects
        .where((effect) => effect.status == EffectStatus.failed)
        .length,
    firstLine: dayAndTime(start, now),
    code: code,
    changedOnResume: switch (state.codes) {
      [final started?, ...final resumed] => resumed.any(
        (code) => code != null && code != started,
      ),
      _ => false,
    },
    from: from,
    problems: session.problems,
  );
}

/// Why a session is `Interrupted`, in the tooltip of its status.
const interruptedWhy =
    'The process that ran this session is gone; resume it to finish.';

/// The mark of a session resumed on code other than it started on
/// (decision 7), on its card and the session bar.
const resumedOnChangedCode = 'resumed on changed code';

/// The mark of a session whose journal was read incompletely: lines that
/// are not events, events this version does not read, files that could not
/// be read (ui-spec «Когда что-то не так»).
const logReadIncompletely = 'Log read incompletely';

/// The most problems the tooltip of [logReadIncompletely] lists.
const problemsShown = 5;

/// What the sessions column says instead of sessions when the workflow has
/// none.
const noSessionsYet = 'No sessions yet';

/// Where the sessions of the graph file [graphFile] come from: the store
/// [watching] (`StorePlace.name`) — by default the `runs` directory of its
/// project (`projectDirOf`), where the workflow library writes them.
String noSessionsHint(String graphFile, {String watching = 'runs/'}) {
  final project = p.basename(projectDirOf(graphFile));
  return 'Sessions of the workflow appear as it runs: '
      'they are read from '
      '${watching == 'runs/' ? 'runs/ in $project/' : watching}.';
}

/// The summaries of [sessions] that have started, newest first; [codeOf]
/// checks the code of each, [fromOf] tells the workflow of a parent's
/// session (`SessionSummary.from`).
List<SessionSummary> sessionSummaries(
  Iterable<SessionData> sessions,
  DateTime now, {
  CodeCheck? Function(SessionData session)? codeOf,
  String? Function(SessionData session)? fromOf,
}) => [
  for (final session in sessionsNewestFirst(sessions))
    summarize(
      session,
      now,
      code: codeOf?.call(session),
      from: fromOf?.call(session),
    )!,
];

/// Those of [sessions] that have started, newest first (ui-spec «Сессии»).
List<SessionData> sessionsNewestFirst(Iterable<SessionData> sessions) {
  final started = [
    for (final session in sessions)
      if (session.state.startedAt case final start?) (session, start),
  ];
  started.sort((a, b) {
    final byTime = b.$2.compareTo(a.$2);
    return byTime != 0 ? byTime : a.$1.id.compareTo(b.$1.id);
  });
  return [for (final (session, _) in started) session];
}

/// The id the sessions of the workflow [name] are listed under: its
/// function's in [graph] (`GraphFile.workflowNamed`), else [name] itself.
String workflowIdOf(GraphFile graph, String name) =>
    graph.workflowNamed(name)?.id ?? name;

/// Those of [sessions] that ran the workflow [workflowId] of [graph]. Every
/// session while no graph file has been read: nothing tells the workflows
/// apart.
List<SessionData> sessionsOfWorkflow(
  Iterable<SessionData> sessions,
  GraphFile? graph,
  String? workflowId,
) => [
  for (final session in sessions)
    if (graph == null ||
        (workflowId != null &&
            workflowIdOf(graph, session.session.workflow) == workflowId))
      session,
];
