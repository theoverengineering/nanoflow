/// What the graph screen shows of a session, derived from what the feed has
/// given (docs/ui-spec.md «Сессии»; spec §9 «Сессия»).
///
/// Pure: no I/O, the time is passed in. Widgets draw what is here and decide
/// nothing about it. The parts are in their own files, exported here.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'freshness.dart';
import 'graph_file_source.dart';
import 'outcomes.dart';
import 'session_feed.dart';
import 'sessions.dart';

export 'freshness.dart' show CodeCheck;
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

/// Everything the graph screen shows of a session at a moment.
final class SessionView {
  SessionView._({
    required this.summary,
    required this.graph,
    required this.stepId,
  });

  /// [session] at [now], with its step [stepId] selected; its snapshot
  /// documents as [documents] has them, the graph file as [graphFile] is
  /// now.
  factory SessionView.of(
    SessionData session, {
    required DateTime now,
    required KnownOutcomes documents,
    required GraphFile? graphFile,
    String? stepId,
  }) => SessionView._(
    summary: summarize(session, now),
    graph: sessionGraphOf(session, documents: documents, graphFile: graphFile),
    stepId: stepId,
  );

  /// `null` while the session's `session-started` has not been read.
  final SessionSummary? summary;

  final SessionGraph graph;

  /// The selected step; `null` when none is.
  final String? stepId;
}
