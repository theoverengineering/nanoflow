/// The sessions column and the session strip over the canvas
/// (docs/ui-spec.md «Сессии»). Pure: the time is passed in.
library;

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import 'freshness.dart' show CodeCheck;
import 'session_feed.dart';
import 'texts.dart';
import 'texts.dart' as texts show shortId;

/// A session's card in the sessions column and its strip over the canvas.
final class SessionSummary {
  SessionSummary._({
    required this.id,
    required this.startedAt,
    required this.status,
    required this.duration,
    required this.steps,
    required this.failedSteps,
    required this.firstLine,
    required this.code,
    required this.changedOnResume,
    required List<String> problems,
  }) : problems = List.unmodifiable(problems);

  final String id;

  String get shortId => texts.shortId(id);

  /// The session's `session-started`, in UTC.
  final DateTime startedAt;

  /// As its last event tells: running until `session-finished` or
  /// `session-failed`.
  final SessionStatus status;

  /// From [startedAt] to the session's last event; for a running session,
  /// to now.
  final Duration duration;

  /// How many steps the session has started.
  final int steps;

  /// How many of them failed the last time they ran.
  final int failedSteps;

  /// The day and time the session started: `Today · 14:03:11`.
  final String firstLine;

  /// How the code the session ran on stands against its graph; `null`
  /// while that is not known.
  final CodeCheck? code;

  /// Whether a resume of the session ran on code other than the code it
  /// started on (decision 7): its steps before that ran on other code. Both
  /// hashes must be known.
  final bool changedOnResume;

  /// [resumedOnChangedCode] on the card and the session bar when the
  /// session [changedOnResume]; `null` when not.
  String? get resumedNote => changedOnResume ? resumedOnChangedCode : null;

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

  /// `Running for 12m 26s`, `Failed in 6m 18s`, `Finished in 3m 04s`.
  String get statusText => switch (status) {
    SessionStatus.running => 'Running for ${formatDuration(duration)}',
    SessionStatus.failed => 'Failed in ${formatDuration(duration)}',
    SessionStatus.finished => 'Finished in ${formatDuration(duration)}',
  };

  /// `1 failed` next to the status of a running session with failed steps:
  /// the workflow caught what they threw, or has not yet.
  String? get failedBadge => status == SessionStatus.running && failedSteps > 0
      ? '$failedSteps failed'
      : null;

  /// `1 step`, `8 steps`.
  String get stepsText => count(steps, 'step');

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

/// The summary of [session] at [now], [code] the check of its code; `null`
/// while its `session-started` has not been read: a session has no start
/// time before that.
SessionSummary? summarize(
  SessionData session,
  DateTime now, {
  CodeCheck? code,
}) {
  final state = session.state;
  final start = state.startedAt;
  if (start == null) return null;
  return SessionSummary._(
    id: session.id,
    startedAt: start,
    status: state.status,
    duration: (state.finishedAt ?? now).difference(start),
    steps: state.steps.length,
    failedSteps: state.steps
        .where((step) => step.status == StepStatus.failed)
        .length,
    firstLine: dayAndTime(start, now),
    code: code,
    changedOnResume: switch (state.codes) {
      [final started?, ...final resumed] => resumed.any(
        (code) => code != null && code != started,
      ),
      _ => false,
    },
    problems: session.problems,
  );
}

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

/// Where the sessions of the graph file [graphFile] come from: the workflow
/// library writes them to the `runs` directory next to it.
String noSessionsHint(String graphFile) =>
    'Sessions of the workflow appear as it runs: '
    'they are read from runs/ next to ${p.basename(graphFile)}.';

/// The summaries of [sessions] that have started, newest first; [codeOf]
/// checks the code of each.
List<SessionSummary> sessionSummaries(
  Iterable<SessionData> sessions,
  DateTime now, {
  CodeCheck? Function(SessionData session)? codeOf,
}) => [
  for (final session in sessionsNewestFirst(sessions))
    summarize(session, now, code: codeOf?.call(session))!,
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

/// A workflow whose sessions the screen can show: one of the graph file's,
/// or one that sessions ran which the graph file does not have — run
/// before the graph file was written again, or renamed or removed since.
final class WorkflowChoice {
  const WorkflowChoice._(this.id, this.name, this.function);

  /// Its function's id in the graph file; for a workflow the graph file
  /// does not have, its name.
  final String id;

  /// The name of the workflow function: what sessions record.
  final String name;

  /// Its function in the graph file; `null` when the file does not have it.
  final GraphFunction? function;

  bool get inGraphFile => function != null;
}

/// The id the sessions of the workflow [name] are listed under: its
/// function's in [graph] (`GraphFile.workflowNamed`), else [name] itself.
String workflowIdOf(GraphFile graph, String name) =>
    graph.workflowNamed(name)?.id ?? name;

/// The workflows of [graph] in its order, then by name those [sessions] ran
/// that it does not have.
List<WorkflowChoice> workflowChoices(
  GraphFile graph,
  Iterable<SessionData> sessions,
) => [
  for (final id in graph.workflows)
    if (graph.functions[id] case final function?)
      WorkflowChoice._(id, function.name, function),
  for (final name in sessionsNotInGraph(graph, sessions).keys)
    WorkflowChoice._(name, name, null),
];

/// How many of [sessions] ran each workflow [graph] does not have, by its
/// name, in the order of the names.
Map<String, int> sessionsNotInGraph(
  GraphFile graph,
  Iterable<SessionData> sessions,
) {
  final counts = <String, int>{};
  for (final session in sessions) {
    final name = session.session.workflow;
    if (graph.workflowNamed(name) == null) {
      counts[name] = (counts[name] ?? 0) + 1;
    }
  }
  return {for (final name in counts.keys.toList()..sort()) name: counts[name]!};
}

/// Those of [sessions] that ran the workflow [workflowId] of [graph] (a
/// [WorkflowChoice.id]). Every session while no graph file has been read:
/// nothing tells the workflows apart.
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
