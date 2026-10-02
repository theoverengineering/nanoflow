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
import 'step_files.dart';
import 'visit_details.dart';
import 'visits.dart' as visits show visitToOpen;
import 'visits.dart' show Visit, visitOf;

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

  /// What the canvas says instead of a graph: [noValidGraphYet],
  /// [unreadableSessionGraph].
  final String? placeholder;

  /// What `nanoflow check` found wrong with the current graph, for
  /// `Current graph`.
  final List<String> errors;
}

/// What the canvas says for a session whose graph is not one the app can
/// read.
const unreadableSessionGraph = 'Graph of this session cannot be read';

/// The graph of the selected [session]: the graph it holds. Without a
/// session (`Current graph`), the last graph that passed check,
/// [currentGraph], with the [errors] of the latest description.
CanvasGraph canvasOf({
  required SessionData? session,
  required Graph? currentGraph,
  required List<String> errors,
}) {
  if (session != null) {
    final graph = session.graph;
    return CanvasGraph._(
      graph: graph,
      ofSession: true,
      placeholder: graph == null ? unreadableSessionGraph : null,
    );
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
/// It feeds new data to the [selection], and reads the fork outcomes of the
/// session it is asked to show, and of no other. Listeners hear of any
/// change; durations that grow with time need a clock besides (`LiveClock`).
/// What it derives is computed once per change and second, so any number of
/// widgets can ask for it.
class GraphModel extends ChangeNotifier {
  /// [now] tells when the graph is opened, for the [selection].
  GraphModel({
    required this.source,
    required this.feed,
    required this.outcomes,
    required this.files,
    DateTime Function()? now,
  }) : selection = Selection(now: now) {
    feed.addListener(_fed);
    outcomes.addListener(_changed);
    source.addListener(_changed);
    selection.addListener(_selected);
    _documents = feed.documentsAdded.listen(
      (document) => outcomes.documentWritten(document.documentId),
    );
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
      files: ReaderFiles(reader),
    );
    unawaited(model.source.start());
    return model;
  }

  final GraphSource source;
  final SessionFeed feed;
  final Outcomes outcomes;
  final Selection selection;

  /// The logs and documents of steps, read when the step details show them.
  final StepFiles files;

  late final StreamSubscription<DocumentAdded> _documents;

  /// Whether the [selection] changes because of new data: the change is told
  /// with the data.
  bool _feeding = false;

  /// Counts the changes: what was derived for an older count is stale.
  int _changes = 0;

  ({int changes, int second})? _sessionsKey;
  List<SessionSummary> _sessions = const [];
  ({int changes, int second})? _viewKey;
  SessionView? _view;

  /// The selected session; `null` for `Current graph`.
  SessionData? get selectedSession {
    final id = selection.sessionId;
    return selection.currentGraph || id == null ? null : feed.session(id);
  }

  /// The sessions column at [now], newest first.
  List<SessionSummary> sessions(DateTime now) {
    final key = _key(now);
    if (key != _sessionsKey) {
      _sessions = List.unmodifiable(
        sessionSummaries(feed.sessions.values, now),
      );
      _sessionsKey = key;
    }
    return _sessions;
  }

  /// The selected session at [now]; `null` for `Current graph`. Starts
  /// reading the outcomes of its forks: they come as a change.
  SessionView? sessionView(DateTime now) {
    final key = _key(now);
    if (key == _viewKey) return _view;
    final session = selectedSession;
    if (session != null) outcomes.load(session.id, forkOutputs(session));
    _view = session == null
        ? null
        : SessionView.of(
            session,
            now: now,
            outcomes: outcomes,
            runId: selection.runId,
            stepId: selection.stepId,
          );
    _viewKey = key;
    return _view;
  }

  ({int changes, int second}) _key(DateTime now) =>
      (changes: _changes, second: now.millisecondsSinceEpoch ~/ 1000);

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

  /// The visit the step details window opens on for a double click on
  /// [node]: the node's last step among the selected run's steps, else its
  /// latest visit in the selected session; `null` when it has none, and for
  /// `Current graph`.
  Visit? visitToOpen(String node) {
    final session = selectedSession;
    return session == null
        ? null
        : visits.visitToOpen(session, selection.runId, node);
  }

  /// Selects the step [stepId] of the selected session, a visit the step
  /// details window shows: closed, the window leaves the canvas and `Logs`
  /// on it.
  void showVisit(String stepId) {
    final session = selectedSession;
    if (session == null) return;
    final visit = visitOf(session, stepId);
    if (visit != null) selection.selectVisit(session, visit.runId, stepId);
  }

  /// The step details window on [node] of the graph on the canvas, at the
  /// visit of the step [stepId] of the selected session, at [now].
  VisitDetails detailsOf(String node, String? stepId, DateTime now) =>
      visitDetails(
        session: selectedSession,
        graph: canvas.graph,
        node: node,
        stepId: stepId,
        now: now,
      );

  void _fed() {
    _feeding = true;
    selection.update(feed.sessions.values);
    _feeding = false;
    _changed();
  }

  void _selected() {
    if (!_feeding) _changed();
  }

  void _changed() {
    _changes++;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_documents.cancel());
    feed.removeListener(_fed);
    outcomes.removeListener(_changed);
    source.removeListener(_changed);
    selection.removeListener(_selected);
    source.dispose();
    feed.dispose();
    outcomes.dispose();
    selection.dispose();
    super.dispose();
  }
}
