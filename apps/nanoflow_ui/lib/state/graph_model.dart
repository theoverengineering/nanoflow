import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_reader/nanoflow_reader.dart';

import '../platform/shell.dart';
import 'graph_source.dart';
import 'outcomes.dart';
import 'selection.dart';
import 'session_feed.dart';
import 'session_view.dart';

/// The graph the canvas shows (docs/ui-spec.md «Что это»: «Граф двух
/// видов»).
final class CanvasGraph {
  const CanvasGraph._({
    required this.graph,
    required this.ofSession,
    this.placeholder,
    this.errors = const [],
  });

  /// `null` when there is no graph to draw.
  final Graph? graph;

  /// Whether [graph] is the selected session's own: then the session's runs,
  /// counters and markers go on it. For `Current graph` they do not.
  final bool ofSession;

  /// What the canvas says instead of a graph: [noValidGraphYet].
  final String? placeholder;

  /// What `nanoflow check` found wrong with the current graph, for
  /// `Current graph`.
  final List<String> errors;
}

/// The graph of the selected [session]: the graph it holds. Without a
/// session (`Current graph`), the last graph that passed check,
/// [currentGraph], with the [errors] of the latest description.
CanvasGraph canvasOf({
  required SessionData? session,
  required Graph? currentGraph,
  required List<String> errors,
}) {
  if (session != null) {
    return CanvasGraph._(graph: session.graph, ofSession: true);
  }
  return CanvasGraph._(
    graph: currentGraph,
    ofSession: false,
    placeholder: currentGraph == null ? noValidGraphYet : null,
    errors: errors,
  );
}

/// The state of one graph screen: the current graph, the sessions, what is
/// selected, the outcomes of forks; everything the screen shows is derived
/// from it.
///
/// It feeds new data to the [selection] and reads the outcomes of the
/// selected session's forks. Listeners hear of any change; durations that
/// grow with time need a clock besides (`LiveClock`).
class GraphModel extends ChangeNotifier {
  GraphModel({
    required this.source,
    required this.feed,
    required this.outcomes,
    Selection? selection,
  }) : selection = selection ?? Selection() {
    feed.addListener(_fed);
    outcomes.addListener(notifyListeners);
    source.addListener(notifyListeners);
    this.selection.addListener(_selected);
  }

  /// The model of the graph file [file]: its current graph from
  /// `nanoflow-yaml`, its sessions from the `runs` directory next to it.
  factory GraphModel.open(String file, Shell shell) {
    final reader = FsReader(
      runsDir: runsDirOf(file),
      graphName: graphNameOf(file),
    );
    final model = GraphModel(
      source: GraphSource(file: file, shell: shell),
      feed: SessionFeed.read(reader),
      outcomes: Outcomes.read(reader),
    );
    unawaited(model.source.start());
    return model;
  }

  final GraphSource source;
  final SessionFeed feed;
  final Outcomes outcomes;
  final Selection selection;

  /// Whether the [selection] changes because of new data: the change is told
  /// with the data.
  bool _feeding = false;

  /// The selected session; `null` for `Current graph`.
  SessionData? get selectedSession {
    final id = selection.sessionId;
    return selection.currentGraph || id == null ? null : feed.session(id);
  }

  /// The sessions column at [now], newest first.
  List<SessionSummary> sessions(DateTime now) =>
      sessionSummaries(feed.sessions.values, now);

  /// The selected session at [now]; `null` for `Current graph`.
  SessionView? sessionView(DateTime now) {
    final session = selectedSession;
    if (session == null) return null;
    return SessionView.of(
      session,
      now: now,
      outcomes: (id) => outcomes[id],
      runId: selection.runId,
      stepId: selection.stepId,
    );
  }

  /// The graph on the canvas.
  CanvasGraph get canvas => canvasOf(
    session: selectedSession,
    currentGraph: source.graph,
    errors: source.errors,
  );

  /// Selects the session [sessionId].
  void showSession(String sessionId) {
    final session = feed.session(sessionId);
    if (session != null) selection.showSession(session);
  }

  /// Selects the run [runId] of the selected session.
  void selectRun(String runId) {
    final session = selectedSession;
    if (session != null) selection.selectRun(session, runId);
  }

  /// Selects the step [stepId] of the selected run.
  void selectStep(String stepId) {
    final session = selectedSession;
    if (session != null) selection.selectStep(session, stepId);
  }

  /// Selects the last step on [node] of the selected run.
  void clickNode(String node) {
    final session = selectedSession;
    if (session != null) selection.clickNode(session, node);
  }

  void _fed() {
    _feeding = true;
    selection.update(feed.sessions.values, loading: feed.loading);
    _feeding = false;
    _readOutcomes();
    notifyListeners();
  }

  void _selected() {
    if (_feeding) return;
    _readOutcomes();
    notifyListeners();
  }

  void _readOutcomes() {
    final session = selectedSession;
    if (session != null) outcomes.load(session.id, forkOutputs(session));
  }

  @override
  void dispose() {
    feed.removeListener(_fed);
    outcomes.removeListener(notifyListeners);
    source.removeListener(notifyListeners);
    selection.removeListener(_selected);
    source.dispose();
    feed.dispose();
    outcomes.dispose();
    selection.dispose();
    super.dispose();
  }
}
