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
import 'in_place.dart';
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
/// `graph`, else [graphFile], the graph file as it is now. A document whose
/// value is `null` — a resume when there was no graph file — is no
/// snapshot: the graph file then too.
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
    if (document != null && document.value == null) {
      // The snapshot of a resume when there was no graph file, as the
      // library wrote it before it wrote none then: no snapshot.
      graph = graphFile;
      noSnapshot = true;
    } else {
      graph = document == null ? null : readGraphFile(document.value);
      unreadable = document == null
          ? documents.problemOf(snapshot) != null
          : graph == null;
    }
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

/// What a session shows in a frame drawn in place (decision 6): what its
/// body would show opened — the copies frames down to it and the steps
/// shown, those of the copies chosen in them — and their marks on its body.
final class FrameScope {
  FrameScope._(this.frame, this.shown, this.marks);

  final InPlaceFrame frame;

  /// The copies frames down to the frame's body, and the steps shown in it.
  final ShownSteps shown;

  /// What the steps shown put on the frame's body.
  final GraphMarks marks;

  /// The frame's own copies, the one chosen, how they stand; `null` for a
  /// call.
  CopiesFrame? get copies => shown.frames
      .where((frame) => frame.depth == this.frame.path.length)
      .firstOrNull;
}

/// No copies chosen in any frame.
Map<int, String> _noCopies(List<Opened> path) => const {};

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
    required this.logsShown,
    required this._session,
    required this._frames,
    required this._scopes,
  });

  /// [session] at [now], with its step [stepId] selected; its snapshot
  /// documents as [documents] has them, the graph file as [graphFile] is
  /// now. [levels] are the levels of its graph drawn, the last of them on
  /// the canvas, its steps found on them by [places] (by default, the
  /// places of its graph's workflow); [copies] the copy selected in each
  /// copies frame among them, by depth.
  ///
  /// [frames] are drawn in place in the last level: each shows what its
  /// body would opened, the copies chosen down to it [copiesIn] the path
  /// to it. `Logs` follow the frame at [follow], as they would its body
  /// opened; the level drawn without it.
  factory SessionView.of(
    SessionData session, {
    required DateTime now,
    required KnownOutcomes documents,
    required GraphFile? graphFile,
    String? stepId,
    List<BodyLevel> levels = const [],
    StepPlaces? places,
    Map<int, String> copies = const {},
    List<InPlaceFrame> frames = const [],
    Map<int, String> Function(List<Opened> path) copiesIn = _noCopies,
    List<Opened>? follow,
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
    final scopes = <String, FrameScope>{
      for (final frame in allFrames(frames))
        levelKey(frame.path): () {
          final inside = framesOf(
            frame.levels,
            places: places!,
            session: session,
            selected: copiesIn(frame.path),
          );
          return FrameScope._(
            frame,
            inside,
            GraphMarks.of(
              frame.level.body,
              places: places,
              session: session,
              steps: inside.steps,
              selectedStepId: stepId,
            ),
          );
        }(),
    };
    final followed = follow == null ? null : scopes[levelKey(follow)];
    final logs = followed?.shown ?? shown;
    final copy = logs.copy;
    // The title names the copies chosen down to the level Logs show; those
    // chosen in frames in it, the rows do.
    final depth = (followed?.frame.levels.length ?? levels.length) - 1;
    String? tagOf(String stepId) => _deepest(
      session,
      places!,
      stepId,
      shown: logs,
      frames: followed?.frame.frames ?? frames,
      scopes: scopes,
    ).tagOf(stepId, upTo: depth);
    return SessionView._(
      summary: summarize(session, now),
      graph: graph,
      stepId: stepId,
      places: places,
      shown: shown,
      logs: (
        header: LogsHeader(logs.steps.length, copy: copy),
        rows: logRows(
          session,
          steps: logs.steps,
          places: places,
          now: now,
          copyOf: tagOf,
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
      logsShown: logs,
      session: session,
      frames: frames,
      scopes: scopes,
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

  /// What `Logs` show: the level drawn, or the frame drawn in place whose
  /// copy they follow.
  final ShownSteps logsShown;

  final SessionData _session;

  /// The frames drawn in place in the level drawn.
  final List<InPlaceFrame> _frames;

  /// What each frame drawn in place shows, by [levelKey] of its path.
  final Map<String, FrameScope> _scopes;

  /// What the frame drawn in place at [path] shows; `null` for one not
  /// drawn.
  FrameScope? scopeOf(List<Opened> path) => _scopes[levelKey(path)];

  /// What the level drawn shows at [path] — its own when [path] is `null`
  /// or no frame of it.
  ShownSteps shownAt(List<Opened>? path) =>
      path == null ? shown : scopeOf(path)?.shown ?? shown;

  /// The copies the step [stepId] is in: `pkg 2 › target 1`; `null` for a
  /// step in no copies frame drawn. The frames drawn in place it is in
  /// name them as its body opened would.
  String? copyOf(String stepId) => _deepest(
    _session,
    places,
    stepId,
    shown: shown,
    frames: _frames,
    scopes: _scopes,
  ).copyOf(stepId);

  /// The nodes to show the step [stepId] at: the node of the level drawn
  /// it is on or in, then, while that node is drawn in place, the node of
  /// its frame it is on or in, and so on; none for a step at no node.
  List<String> revealPathOf(String stepId) {
    final nodes = <String>[];
    var marks = this.marks;
    var frames = _frames;
    while (marks != null) {
      final node = marks.nodesOf(stepId).firstOrNull;
      if (node == null) break;
      nodes.add(node);
      final frame = frames.where((f) => f.nodeId == node).firstOrNull;
      if (frame == null) break;
      marks = scopeOf(frame.path)?.marks;
      frames = frame.frames;
    }
    return nodes;
  }
}

/// What names the copies of the step [stepId] of [session] best: the
/// deepest frame drawn in place that holds it, from [frames] down — else
/// [shown].
ShownSteps _deepest(
  SessionData session,
  StepPlaces places,
  String stepId, {
  required ShownSteps shown,
  required List<InPlaceFrame> frames,
  required Map<String, FrameScope> scopes,
}) {
  final record = session.steps[stepId];
  for (final frame in frames) {
    if (!places.isIn(record, frame.node)) continue;
    final scope = scopes[levelKey(frame.path)];
    if (scope == null) continue;
    return _deepest(
      session,
      places,
      stepId,
      shown: scope.shown,
      frames: frame.frames,
      scopes: scopes,
    );
  }
  return shown;
}
