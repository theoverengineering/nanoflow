import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_reader/nanoflow_reader.dart';
import 'package:path/path.dart' as p;

import 'body_path.dart';
import 'canvas_graph.dart';
import 'copies.dart';
import 'copy_choices.dart' as choices show hintOf;
import 'copy_choices.dart' show CopyChoices, hintDocuments;
import 'freshness.dart';
import 'graph_file_source.dart';
import 'outcomes.dart';
import 'selection.dart';
import 'session_feed.dart';
import 'session_view.dart';
import 'step_files.dart';
import 'visit_details.dart';
import 'visits.dart' as visits show visitToOpen;
import 'visits.dart' show Visit;

export 'canvas_graph.dart';

/// The state of one graph screen: the graph file and how it stands against
/// the code, the sessions of its selected workflow, what is selected, the
/// snapshot documents read; everything the screen shows is derived from it.
///
/// It feeds new data to the [selection], and reads the snapshot of the
/// session it is asked to show, and of no other. Listeners hear of any
/// change; durations that grow with time need a clock besides (`LiveClock`).
/// What it derives is computed once per change and second, so any number of
/// widgets can ask for it.
class GraphModel extends ChangeNotifier {
  /// [now] tells when the graph is opened, for the [selection].
  GraphModel({
    required this.graphFile,
    required this.freshness,
    required this.feed,
    required this.outcomes,
    required this.files,
    DateTime Function()? now,
  }) : selection = Selection(now: now),
       _now = now ?? DateTime.now {
    graphFile.addListener(_graphFileChanged);
    freshness.addListener(_changed);
    feed.addListener(_fed);
    outcomes.addListener(_changed);
    selection
      ..addListener(_selected)
      ..lastStepOf = _lastShownStep;
    _documents = feed.documentsAdded.listen(
      (document) => outcomes.documentWritten(document.documentId),
    );
  }

  /// The model of the graph file [file]: the file, read and followed, and
  /// checked against the code next to it; the sessions in the `runs`
  /// directory next to it.
  factory GraphModel.open(String file) {
    final reader = FsReader(runsDir: runsDirOf(p.dirname(file)));
    final graphFile = GraphFileSource(file: file);
    final model = GraphModel(
      graphFile: graphFile,
      freshness: FreshnessWatch(graphFile),
      feed: SessionFeed.read(reader),
      outcomes: Outcomes.read(reader),
      files: ReaderFiles(reader),
    );
    unawaited(graphFile.start());
    model.freshness.start();
    return model;
  }

  final GraphFileSource graphFile;
  final FreshnessWatch freshness;
  final SessionFeed feed;

  /// The values of documents read on request: the snapshots of sessions.
  final Outcomes outcomes;
  final Selection selection;

  /// The logs and documents of steps, read when the step details show them.
  final StepFiles files;

  late final StreamSubscription<DocumentAdded> _documents;

  /// The workflow the user chose, by its id and its name: [workflow] finds
  /// it by its name when its id has changed, as when describe writes a
  /// workflow its sessions ran to the graph file; it falls back to the
  /// first.
  ({String id, String name})? _chosen;

  /// The levels opened under the workflow's body: the canvas goes down them
  /// as far as the graph it draws has them.
  List<Opened> _path = const [];

  /// The time, for what is derived at a moment.
  final DateTime Function() _now;

  /// The copies chosen in the copies frames of the selected session.
  final _copies = CopyChoices();

  /// Whether the [selection] changes because of new data: the change is told
  /// with the data.
  bool _feeding = false;

  /// Counts the changes: what was derived for an older count is stale.
  int _changes = 0;

  ({int changes, int second})? _sessionsKey;
  List<SessionSummary> _sessions = const [];
  ({int changes, int second})? _viewKey;
  SessionView? _view;
  int? _canvasKey;
  CanvasGraph? _canvas;

  /// The workflows to choose from: the graph file's in its order, then
  /// those sessions ran that it does not have (`workflowChoices`); none
  /// while no graph file has been read.
  List<WorkflowChoice> get workflows {
    final graph = graphFile.graph;
    return graph == null
        ? const []
        : workflowChoices(graph, feed.sessions.values);
  }

  /// The selected workflow: the one chosen while it is listed, by its id or
  /// else its name; else the first; `null` without workflows.
  WorkflowChoice? get workflow {
    final all = workflows;
    final chosen = _chosen;
    return all.where((w) => w.id == chosen?.id).firstOrNull ??
        all.where((w) => w.name == chosen?.name).firstOrNull ??
        all.firstOrNull;
  }

  /// Selects the workflow [id] (a [WorkflowChoice.id]), drawn from its top
  /// level. Another workflow's sessions open as on opening the graph: its
  /// newest session started before now is selected.
  void selectWorkflow(String id) {
    final choice = workflows.where((w) => w.id == id).firstOrNull;
    if (choice == null) return;
    _path = const [];
    if (id != workflow?.id) {
      _chosen = (id: choice.id, name: choice.name);
      selection.reopen();
      _feedSelection();
    }
    _changed();
  }

  /// Opens [opened], a node of the body drawn, one level down
  /// (`openings`).
  void open(Opened opened) {
    _path = [...canvas.path, opened];
    _changed();
  }

  /// Goes back to the level [depth] of the canvas's levels: 0 for the
  /// workflow's body.
  void openLevel(int depth) {
    _path = canvas.path.take(depth).toList();
    _changed();
  }

  /// The sessions of the selected workflow as the feed has them: every
  /// session while no graph file has been read.
  List<SessionData> get workflowSessions =>
      sessionsOfWorkflow(feed.sessions.values, graphFile.graph, workflow?.id);

  /// The selected session; `null` for `Current graph`.
  SessionData? get selectedSession {
    final id = selection.sessionId;
    return selection.currentGraph || id == null ? null : feed.session(id);
  }

  /// The sessions column at [now], newest first, the code of each checked
  /// against its graph.
  List<SessionSummary> sessions(DateTime now) {
    final key = _key(now);
    if (key != _sessionsKey) {
      _sessions = List.unmodifiable(
        sessionSummaries(
          workflowSessions,
          now,
          // A snapshot of a resume is read only for the session shown: the
          // others are checked once it has been read.
          codeOf: (session) => sessionGraphOf(
            session,
            documents: outcomes,
            graphFile: graphFile.graph,
          ).code,
        ),
      );
      _sessionsKey = key;
    }
    return _sessions;
  }

  /// The selected session at [now]; `null` for `Current graph`. Starts
  /// reading its snapshot, and the outputs of the first steps of the
  /// copies of its frames drawn: they come as a change.
  SessionView? sessionView(DateTime now) {
    final key = _key(now);
    if (key == _viewKey) return _view;
    final session = _readSelected();
    _view = session == null
        ? null
        : SessionView.of(
            session,
            now: now,
            documents: outcomes,
            graphFile: graphFile.graph,
            stepId: selection.stepId,
            levels: canvas.ofSession ? canvas.levels : const [],
            places: canvas.ofSession ? canvas.places : null,
            copies: _copies.on(canvas.path),
          );
    // What the copies' first steps gave tells them apart: read it now.
    if (session != null) {
      outcomes.load(session.id, hintDocuments(_view!.shown));
    }
    _viewKey = key;
    return _view;
  }

  /// The graph on the canvas. Starts reading the selected session's
  /// snapshot: it comes as a change.
  CanvasGraph get canvas {
    if (_canvasKey == _changes) return _canvas!;
    final session = _readSelected();
    final graph = graphFile.graph;
    final workflow = this.workflow;
    final notes = graph == null
        ? const <GraphNote>[]
        : workflowNotes(
            file: graphFile.file,
            workflow: workflow,
            notInGraph: sessionsNotInGraph(graph, feed.sessions.values),
          );
    final canvas = session == null
        ? fileCanvas(
            file: graphFile.file,
            graph: graph,
            workflowId: workflow?.id,
            path: _path,
            error: graphFile.error,
            fileMissing: graphFile.fileMissing,
            freshness: freshness.freshness,
            extraNotes: notes,
          )
        : sessionCanvas(
            session,
            sessionGraphOf(session, documents: outcomes, graphFile: graph),
            path: _path,
            extraNotes: notes,
          );
    _canvasKey = _changes;
    return _canvas = canvas;
  }

  /// The selected session, whose snapshot document starts being read.
  SessionData? _readSelected() {
    final session = selectedSession;
    if (session != null) {
      outcomes.load(session.id, [?snapshotDocumentOf(session)]);
    }
    return session;
  }

  ({int changes, int second}) _key(DateTime now) =>
      (changes: _changes, second: now.millisecondsSinceEpoch ~/ 1000);

  /// Selects the session [sessionId].
  void showSession(String sessionId) {
    final session = feed.session(sessionId);
    if (session != null) selection.showSession(session);
  }

  /// The copies frames of the canvas's levels and the steps they show, of
  /// the selected session on its own graph, as [sessionView] has them at
  /// [now]; `null` for `Current graph`.
  ShownSteps? _shown(DateTime now) =>
      canvas.ofSession ? sessionView(now)?.shown : null;

  /// The frames and steps shown of [session] as they are now, the copies
  /// chosen as they are now: for what changes them before [sessionView]
  /// can tell.
  ShownSteps? _shownNow(SessionData session) {
    final canvas = this.canvas;
    if (!canvas.ofSession) return null;
    return framesOf(
      canvas.levels,
      places: canvas.places,
      session: session,
      selected: _copies.on(canvas.path),
    );
  }

  /// The last of the steps of [session] shown, while copies of it are
  /// chosen: the selection follows the copy shown; `null` otherwise.
  String? _lastShownStep(SessionData session) => _copies.anyFor(session.id)
      ? _shownNow(session)?.steps.lastOrNull?.stepId
      : null;

  /// Shows the copy [copyId] — the id of its first step — of the copies
  /// frame at the level [depth] of the canvas, and selects its last step;
  /// every copy for `null` (decision 11).
  void selectCopy(int depth, String? copyId) {
    final session = selectedSession;
    if (session == null) return;
    _copies.choose(session.id, canvas.path, depth, copyId);
    final frame = _shownNow(session)?.frames
        .where((f) => f.depth == depth)
        .firstOrNull;
    final last = frame?.selected?.steps.lastOrNull;
    if (last != null) selection.selectStep(session, last.stepId);
    _changed();
  }

  /// What the first step of [copy] of the selected session gave, to tell
  /// the copy by (`copyHint`); `null` while it is not known: [sessionView]
  /// reads it.
  String? hintOf(Copy copy) => choices.hintOf(copy, outcomes);

  /// A click on the node [nodeId] of the body drawn: selects the last of
  /// the steps shown on it or in it; nothing without one.
  void clickNode(String nodeId) {
    final session = selectedSession;
    final node = canvas.body?.node(nodeId);
    final shown = _shown(_now());
    if (session == null || node == null || shown == null) return;
    final last = shown.steps
        .where((s) => canvas.places.isIn(session.steps[s.stepId]?.place, node))
        .lastOrNull;
    if (last != null) selection.selectStep(session, last.stepId);
  }

  /// The visit the step details window opens on for a double click on the
  /// step node [node]: its last step among those shown; `null` when it has
  /// none, and for `Current graph`.
  Visit? visitToOpen(StepNode node) {
    final session = selectedSession;
    final shown = _shown(_now());
    if (session == null || shown == null) return null;
    return visits.visitToOpen(session, shown.steps, canvas.places, node);
  }

  /// Selects the step [stepId] of the selected session, a visit the step
  /// details window shows, so that the canvas and `Logs` are on it.
  void showVisit(String stepId) => selectStep(stepId);

  /// The step details window on the step [stepId] of the selected session,
  /// among the steps shown, at [now]; on the step node [node] alone without
  /// a step.
  VisitDetails detailsOf(StepNode? node, String? stepId, DateTime now) {
    final shown = _shown(now);
    return visitDetails(
      session: shown == null ? null : selectedSession,
      steps: shown?.steps ?? const [],
      places: canvas.places,
      stepId: stepId,
      node: node,
      copyOf: shown?.copyOf,
      now: now,
    );
  }

  /// Selects the step [stepId] of the selected session.
  void selectStep(String stepId) {
    final session = selectedSession;
    if (session != null) selection.selectStep(session, stepId);
  }

  void _fed() {
    _feedSelection();
    _changed();
  }

  void _graphFileChanged() {
    // Which sessions are the workflow's may have changed.
    _feedSelection();
    _changed();
  }

  /// Gives the [selection] the sessions of the workflow. A selected session
  /// that is no longer one of them — the graph file changed which workflow
  /// it ran, or which workflow is selected — gives way as on opening the
  /// graph.
  void _feedSelection() {
    _feeding = true;
    final sessions = workflowSessions;
    final selected = selection.sessionId;
    if (selected != null && sessions.every((s) => s.id != selected)) {
      selection.reopen();
    }
    selection.update(sessions);
    _feeding = false;
  }

  void _selected() {
    // The copies chosen are the session's.
    _copies.keepFor(selection.sessionId);
    if (!_feeding) _changed();
  }

  void _changed() {
    _changes++;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_documents.cancel());
    graphFile.removeListener(_graphFileChanged);
    freshness.removeListener(_changed);
    feed.removeListener(_fed);
    outcomes.removeListener(_changed);
    selection.removeListener(_selected);
    freshness.dispose();
    graphFile.dispose();
    feed.dispose();
    outcomes.dispose();
    selection.dispose();
    super.dispose();
  }
}
