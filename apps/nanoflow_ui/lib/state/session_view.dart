/// What the graph screen shows of a session, derived from what the feed has
/// given (docs/ui-spec.md «Сессии»; spec §9 «Сессия»).
///
/// Pure: no I/O, the time is passed in. Widgets draw what is here and decide
/// nothing about it. The parts are in their own files, exported here.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'body_path.dart';
import 'copies.dart';
import 'freshness.dart';
import 'graph_file_source.dart';
import 'graph_marks.dart';
import 'log_rows.dart';
import 'outcomes.dart';
import 'session_feed.dart';
import 'sessions.dart';
import 'step_details.dart';
import 'step_places.dart';

export 'copies.dart' show Copy, CopiesFrame, CopyStatus, ShownSteps;
export 'freshness.dart' show CodeCheck;
export 'graph_marks.dart';
export 'log_rows.dart';
export 'sessions.dart';
export 'step_details.dart';

/// The graph a session is shown on, and how the code it ran on stands
/// against it (spec §9 «Сессия», decision 8).
final class SessionGraph {
  const SessionGraph._({
    required this.graph,
    required this.noSnapshot,
    required this.unreadable,
    required this.code,
  });

  /// The graph file the session is shown on: the snapshot of its last
  /// resume that has one, else the one it was created with, else the graph
  /// file. `null` while the snapshot is being read, when it cannot be read,
  /// and when there is neither a snapshot nor a graph file.
  final GraphFile? graph;

  /// Whether the session holds no snapshot, so that [graph] is the graph
  /// file's: «у сессии нет снимка».
  final bool noSnapshot;

  /// Whether the session's snapshot cannot be read: its document cannot,
  /// or what it holds is not a graph file.
  final bool unreadable;

  /// Whether the session's last code is that of [graph]; `null` without
  /// [graph].
  final CodeCheck? code;
}

/// The graph [session] is shown on: the document of its last
/// `session-resumed` that names one, as [documents] has it, else its own
/// `graph`, else [graphFile], the graph file as it is now.
///
/// The code checked is the session's last: of its last `session-resumed`,
/// else of its `session-started`. Its snapshot is that of the same moment.
SessionGraph sessionGraphOf(
  SessionData session, {
  required KnownOutcomes documents,
  required GraphFile? graphFile,
}) {
  final state = session.state;
  final GraphFile? graph;
  var unreadable = false;
  var noSnapshot = false;
  if (state.graphIds.lastOrNull case final snapshot?) {
    final document = documents[snapshot];
    graph = document == null ? null : readGraphFile(document.value);
    unreadable = document == null
        ? documents.problemOf(snapshot) != null
        : graph == null;
  } else if (session.session.graph case final snapshot?) {
    graph = readGraphFile(snapshot);
    unreadable = graph == null;
  } else {
    graph = graphFile;
    noSnapshot = true;
  }
  return SessionGraph._(
    graph: graph,
    noSnapshot: noSnapshot,
    unreadable: unreadable,
    code: graph == null ? null : checkCode(state.codes.lastOrNull, graph),
  );
}

/// The document with the snapshot [session] is shown on, which is read on
/// request; `null` when its snapshot is in the session itself, or it has
/// none.
String? snapshotDocumentOf(SessionData session) =>
    session.state.graphIds.lastOrNull;

/// The `Logs` panel of a session: its title, its rows and their time scale.
typedef LogsView = ({LogsHeader header, List<LogRow> rows, TimeScale scale});

/// Everything the graph screen shows of a session at a moment: its card,
/// its graph, and its steps on the levels of the graph drawn — the copies
/// frames gone down through, the steps shown, the `Logs`, the selected
/// step, the marks on the level drawn.
final class SessionView {
  SessionView._({
    required this.summary,
    required this.graph,
    required this.stepId,
    required this.places,
    required this.shown,
    required this.logs,
    required this.step,
    required this.marks,
  });

  /// [session] at [now], with its step [stepId] selected; its snapshot
  /// documents as [documents] has them, the graph file as [graphFile] is
  /// now. [levels] are the levels of its graph drawn, the last of them on
  /// the canvas, its steps found on them by [places] (by default, the
  /// places of its graph's workflow); [copies] the copy selected in each
  /// copies frame among them, by depth.
  factory SessionView.of(
    SessionData session, {
    required DateTime now,
    required KnownOutcomes documents,
    required GraphFile? graphFile,
    String? stepId,
    List<BodyLevel> levels = const [],
    StepPlaces? places,
    Map<int, String> copies = const {},
  }) {
    final graph = sessionGraphOf(
      session,
      documents: documents,
      graphFile: graphFile,
    );
    final file = graph.graph;
    places ??= StepPlaces.of(
      file?.workflowNamed(session.session.workflow),
      file?.functions ?? const {},
    );
    final shown = framesOf(
      levels,
      places: places,
      session: session,
      selected: copies,
    );
    final copy = shown.copy;
    return SessionView._(
      summary: summarize(session, now),
      graph: graph,
      stepId: stepId,
      places: places,
      shown: shown,
      logs: (
        header: LogsHeader(shown.steps.length, copy: copy),
        rows: logRows(
          session,
          steps: shown.steps,
          places: places,
          now: now,
          copies: shown.copyNumbers,
          end: copy == null,
        ),
        scale: timeScale(session, now),
      ),
      step: stepId == null ? null : stepDetails(session, stepId),
      marks: levels.isEmpty
          ? null
          : GraphMarks.of(
              levels.last.body,
              places: places,
              session: session,
              steps: shown.steps,
              selectedStepId: stepId,
            ),
    );
  }

  /// `null` while the session's `session-started` has not been read.
  final SessionSummary? summary;

  final SessionGraph graph;

  /// The selected step; `null` when none is.
  final String? stepId;

  /// Which nodes of the graph the session's steps are on.
  final StepPlaces places;

  /// The copies frames the levels drawn go down through, and the steps
  /// shown: those of the copies selected in them.
  final ShownSteps shown;

  final LogsView logs;

  /// The selected step's details; `null` without one.
  final StepDetails? step;

  /// What the steps shown put on the level drawn; `null` without one.
  final GraphMarks? marks;

  /// The copies frames the levels drawn go down through.
  List<CopiesFrame> get frames => shown.frames;

  /// The steps shown, in the order of their first `step-started`.
  List<StepState> get steps => shown.steps;

  /// The copies the step [stepId] is in: `copy 2 › copy 1`; `null` for a
  /// step in no copies frame drawn.
  String? copyOf(String stepId) => shown.copyOf(stepId);
}
