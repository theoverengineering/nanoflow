/// What the graph screen shows of a session, derived from what the feed has
/// given (docs/ui-spec.md «Сессии»; spec §9 «Сессия»).
///
/// Pure: no I/O, the time is passed in. Widgets draw what is here and decide
/// nothing about it. The parts are in their own files, exported here.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'body_path.dart';
import 'effect_details.dart';
import 'effect_places.dart';
import 'freshness.dart';
import 'graph_file_source.dart';
import 'graph_marks.dart';
import 'in_place.dart';
import 'log_rows.dart';
import 'outcomes.dart';
import 'session_feed.dart';
import 'sessions.dart';

export 'effect_details.dart';
export 'freshness.dart' show CodeCheck;
export 'graph_marks.dart';
export 'log_rows.dart';
export 'sessions.dart';

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

/// What a session shows in a frame drawn in place (decision 6): the marks of
/// its effects on its body, the forks their code went through there among
/// them.
final class FrameScope {
  FrameScope._(this.frame, this.marks);

  final InPlaceFrame frame;

  /// What the effects put on the frame's body: their own passes, as on that
  /// body opened, not the level's.
  final GraphMarks marks;
}

/// Everything the graph screen shows of a session at a moment: its card,
/// its graph, and its effects on the levels of the graph drawn — the
/// `Logs`, the selected effect, the marks on the level drawn and on the
/// frames drawn in place in it.
final class SessionView {
  SessionView._({
    required this.summary,
    required this.graph,
    required this.effectId,
    required this.places,
    required this.effects,
    required this.logs,
    required this.logsEffects,
    required this.effect,
    required this.marks,
    required this._frames,
    required this._scopes,
  });

  /// [session] at [now], with its effect [effectId] selected; its snapshot
  /// documents as [documents] has them, the graph file as [graphFile] is
  /// now. [levels] are the levels of its graph drawn, the last of them on
  /// the canvas, its effects found on them by [places] (by default, the
  /// places of its graph's workflow).
  ///
  /// [frames] are drawn in place in the last level: each has the marks of
  /// the effects on its body, as that body opened would.
  ///
  /// [calledGraph] is the id of the called graph opened when [levels] are
  /// of it in a parent's session (`CanvasGraph.calledGraph`): `Logs` list
  /// the effects in it alone, without the session's end.
  ///
  /// `Logs` put each run of a call of the workflow — or of the called graph
  /// opened — on one row; those whose keys are in [openRuns] are open.
  factory SessionView.of(
    SessionData session, {
    required DateTime now,
    required KnownOutcomes documents,
    required GraphFile? graphFile,
    String? effectId,
    List<BodyLevel> levels = const [],
    EffectPlaces? places,
    String? calledGraph,
    List<InPlaceFrame> frames = const [],
    Set<String> openRuns = const {},
  }) {
    final graph = sessionGraphOf(
      session,
      documents: documents,
      graphFile: graphFile,
    );
    final file = graph.graph;
    places ??= EffectPlaces.of(
      file?.workflowNamed(session.session.workflow),
      file?.functions ?? const {},
    );
    final effects = session.state.effects;
    final scopes = <String, FrameScope>{
      for (final frame in allFrames(frames))
        levelKey(frame.path): FrameScope._(
          frame,
          GraphMarks.of(
            frame.level.body,
            places: places,
            session: session,
            effects: effects,
            selectedEffectId: effectId,
          ),
        ),
    };
    final logs = calledGraph == null
        ? effects
        : [
            for (final effect in effects)
              if (places.isInFunction(
                session.effects[effect.effectId],
                calledGraph,
              ))
                effect,
          ];
    return SessionView._(
      summary: summarize(session, now),
      graph: graph,
      effectId: effectId,
      places: places,
      effects: effects,
      logs: (
        header: LogsHeader(logs.length),
        rows: logRows(
          session,
          effects: logs,
          places: places,
          now: now,
          calls: switch (calledGraph == null
              ? file?.workflowNamed(session.session.workflow)
              : file?.functions[calledGraph]) {
            final function? => callsIn(function.body),
            null => const [],
          },
          open: openRuns,
          end: calledGraph == null,
        ),
        scale: timeScale(session, now),
      ),
      logsEffects: logs,
      effect: effectId == null ? null : effectDetails(session, effectId),
      marks: levels.isEmpty
          ? null
          : GraphMarks.of(
              levels.last.body,
              places: places,
              session: session,
              effects: effects,
              selectedEffectId: effectId,
            ),
      frames: frames,
      scopes: scopes,
    );
  }

  /// `null` while the session's `session-started` has not been read.
  final SessionSummary? summary;

  final SessionGraph graph;

  /// The selected effect; `null` when none is.
  final String? effectId;

  /// Which nodes of the graph the session's effects are on.
  final EffectPlaces places;

  /// The session's effects, in the order of their first `effect-started`.
  final List<EffectState> effects;

  final LogsView logs;

  /// The effects `Logs` show: all of [effects], or those in the called graph
  /// opened in a parent's session.
  final List<EffectState> logsEffects;

  /// The selected effect's details; `null` without one.
  final EffectDetails? effect;

  /// What the effects put on the level drawn; `null` without one.
  final GraphMarks? marks;

  /// The frames drawn in place in the level drawn.
  final List<InPlaceFrame> _frames;

  /// What each frame drawn in place shows, by [levelKey] of its path.
  final Map<String, FrameScope> _scopes;

  /// What the frame drawn in place at [path] shows; `null` for one not
  /// drawn.
  FrameScope? scopeOf(List<Opened> path) => _scopes[levelKey(path)];

  /// The nodes to show the effect [effectId] at: the node of the level drawn
  /// it is on or in, then, while that node is drawn in place, the node of
  /// its frame it is on or in, and so on; none for an effect at no node.
  List<String> revealPathOf(String effectId) {
    final nodes = <String>[];
    var marks = this.marks;
    var frames = _frames;
    while (marks != null) {
      final node = marks.nodesOf(effectId).firstOrNull;
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
