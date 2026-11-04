import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nanoflow_model/nanoflow_model.dart';

import 'body_path.dart';
import 'called_graph.dart';
import 'canvas_graph.dart';
import 'effect_files.dart';
import 'freshness.dart';
import 'graph_file_source.dart';
import 'in_place.dart';
import 'node_keys.dart';
import 'outcomes.dart';
import 'selection.dart';
import 'session_feed.dart';
import 'session_view.dart';
import 'store_place.dart';
import 'visit_details.dart';
import 'visits.dart' as visits show visitToOpen;
import 'visits.dart' show Visit;

export 'canvas_graph.dart';

/// The state of one graph screen: the graph file and how it stands against
/// the code, the sessions of its graph — or of a graph it calls opened as
/// the main graph, its called graph —, what is selected, the levels opened and the nodes expanded in place, the
/// snapshot documents read; everything the screen shows is derived from it.
///
/// It feeds new data to the [selection], and reads the snapshot of the
/// session it is asked to show, and those the sessions column checks the
/// code of its sessions against. Listeners hear of any
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
    this.watching = 'runs/',
    String? session,
    DateTime Function()? now,
  }) : selection = Selection(now: now),
       _wantedSession = session {
    _graphRead = graphFile.graph;
    graphFile.addListener(_graphFileChanged);
    freshness.addListener(_changed);
    feed.addListener(_fed);
    outcomes.addListener(_outcomesRead);
    selection
      ..addListener(_selected)
      ..lastEffectOf = _lastShownEffect;
    _documents = feed.documentsAdded.listen(
      (document) => outcomes.documentWritten(document.documentId),
    );
  }

  /// The model of the graph file [file]: the file, read and followed, and
  /// checked against the code next to it; the sessions in [store], by
  /// default the `runs` directory next to it, [session] selected once the
  /// feed gives it.
  factory GraphModel.open(String file, {StorePlace? store, String? session}) {
    final place = store ?? StorePlace.nextTo(file);
    final reader = place.reader();
    final graphFile = GraphFileSource(file: file);
    final model = GraphModel(
      graphFile: graphFile,
      freshness: FreshnessWatch(graphFile),
      feed: SessionFeed.read(reader),
      outcomes: Outcomes.read(reader),
      files: ReaderFiles(reader),
      watching: place.name,
      session: session,
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

  /// The logs and documents of effects, read when the effect details show them.
  final EffectFiles files;

  /// What the store of the sessions is called (`StorePlace.name`): `runs/`,
  /// or the database's file name.
  final String watching;

  late final StreamSubscription<DocumentAdded> _documents;

  /// The id of the function the workflow calls opened as the main graph
  /// (open-as-graph design): it is drawn instead of the workflow while the
  /// graph file has it. `null` while none is open.
  String? _called;

  /// Whether each session ran a function — the workflow, or the called
  /// graph open — as a parent's session, by the session's id and the
  /// function's, with what that was told from (`_ranIn`).
  final Map<(String, String), _Ran> _ranOf = {};

  /// The levels opened under the main graph's body: the canvas goes down
  /// them as far as the graph it draws has them.
  List<Opened> _path = const [];

  /// The nodes of the levels opened last, by their keys ([pathKeys]), while
  /// a graph file written again has not all of them: [_path] goes down them
  /// again as far as the graph file has them. `null` while [_path] has them
  /// all.
  List<(String, String?)>? _wanted;

  /// The session to select once the feed gives it and the graph file is
  /// read — as the app was started with it —; `null` once selected, or for
  /// none. Until then no session is selected.
  String? _wantedSession;

  /// The runs of calls open in `Logs`, by key: those of the session
  /// [_runsOf], gone when another is selected.
  final _openRuns = <String>{};
  String? _runsOf;

  /// The nodes expanded in place: they stay for any session of the main
  /// graph, go as another main graph is drawn, and follow their nodes into a
  /// graph file written again ([_carryOver]).
  final _expansions = Expansions();

  /// The graph file read last: the levels opened and the nodes expanded
  /// follow their nodes into another one.
  GraphFile? _graphRead;

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

  /// The graph of the graph file, its workflow: the first of its workflows,
  /// the one a graph's own file has; `null` while no graph file has been
  /// read.
  GraphFunction? get workflow {
    final graph = graphFile.graph;
    return graph?.functions[graph.workflows.firstOrNull];
  }

  /// The function the workflow calls opened as the main graph, as the graph
  /// file has it; `null` while none is open, or the graph file does not
  /// have it.
  GraphFunction? get calledGraph => graphFile.graph?.functions[_called];

  /// The graph drawn from the top level of the canvas: the [calledGraph]
  /// open, else the [workflow].
  GraphFunction? get mainGraph => calledGraph ?? workflow;

  /// Closes the called graph open, back to the [workflow] drawn from its
  /// top level (the parent's crumb): the levels opened and the nodes
  /// expanded go; the selected session stays while it is one of the
  /// workflow's.
  void closeCalledGraph() {
    if (_called == null) return;
    _called = null;
    _path = const [];
    _wanted = null;
    _expansions.clear();
    _mainGraphChanged();
    _changed();
  }

  /// Opens the function [functionId] of the graph file as the main graph
  /// (open-as-graph design §3): drawn from its top, its sessions listed —
  /// those of the workflow it ran in ([workflowSessions]). The levels
  /// opened and the nodes expanded go; the selected session stays while the
  /// function ran in it. Nothing opens
  /// while the graph file does not have the function.
  void openAsGraph(String functionId) {
    if (graphFile.graph?.functions[functionId] == null) return;
    _called = functionId;
    _path = const [];
    _wanted = null;
    _expansions.clear();
    _mainGraphChanged();
    _changed();
  }

  /// What the ↗ on [node] opens as the main graph: the functions of a call
  /// that the graph file has (`openings`) — the canvas may draw a session's
  /// snapshot, with functions renamed or gone since; none for any other
  /// node.
  List<Opened> graphOpenings(GraphNode node) => node is CallNode
      ? openings(node, graphFile.graph?.functions ?? const {})
      : const [];

  /// Gives the [selection] the sessions of the main graph drawn now: the
  /// selected session stays while it is one of them — kept as one chosen,
  /// even if it was selected as the graph opened, so that the newest of the
  /// others does not take its place —; else, and for `Current graph`, they
  /// open as on opening the graph.
  void _mainGraphChanged() {
    final session = selectedSession;
    if (session != null && workflowSessions.any((s) => s.id == session.id)) {
      selection.showSession(session);
    } else {
      selection.reopen();
    }
    _feedSelection();
  }

  /// Opens [opened], a node of the body drawn — or of the body of the frame
  /// drawn in place at [from] — one level down (`openings`).
  void open(Opened opened, {List<Opened>? from}) {
    _path = [...from ?? canvas.path, opened];
    _wanted = null;
    _changed();
  }

  /// Expands [opened], a node of the body at [path] — the body drawn, or
  /// one drawn in place — in place (decision 6).
  void expandNode(List<Opened> path, Opened opened) {
    _expansions.expand(path, opened);
    _changed();
  }

  /// Collapses the node [nodeId] of the body at [path] back to its tile.
  void collapseNode(List<Opened> path, String nodeId) {
    _expansions.collapse(path, nodeId);
    _changed();
  }

  /// Goes back to the level [depth] of the canvas's levels: 0 for the
  /// workflow's body.
  void openLevel(int depth) {
    _path = canvas.path.take(depth).toList();
    _wanted = null;
    _changed();
  }

  /// The sessions of the workflow as the feed has them: every session while
  /// no graph file has been read. Those it ran in (sessions-of-a-graph
  /// design §2): its own, and those of other graphs in which an effect is
  /// in its body — by their places on their snapshots, which start being
  /// read: they come as a change. With a called graph open, those of them
  /// it ran in (§3).
  List<SessionData> get workflowSessions {
    final graph = graphFile.graph;
    final workflow = this.workflow;
    if (graph == null || workflow == null) {
      return sessionsOfWorkflow(feed.sessions.values, graph, workflow?.id);
    }
    final called = calledGraph;
    return [
      for (final session in feed.sessions.values)
        if ((ranAsWorkflow(session, graph, workflow) ||
                _ranIn(session, graph, workflow)) &&
            (called == null || _ranIn(session, graph, called)))
          session,
    ];
  }

  /// Whether [function] of [graph] ran in [session] as a parent's session,
  /// on the graph it is shown on (`ranIn`), where it is found by
  /// `functionIdIn`: worked out again only once its snapshot has changed,
  /// or the graph file for a session shown on it, or — while it had not run
  /// there — the session. Effects are only added, so one that ran stays so.
  /// Starts reading the snapshot.
  bool _ranIn(SessionData session, GraphFile graph, GraphFunction function) {
    final document = snapshotDocumentOf(session);
    if (document != null) outcomes.load(session.id, [document]);
    final snapshot = document == null ? null : outcomes[document];
    final key = (session.id, function.id);
    final known = _ranOf[key];
    if (known != null &&
        known.document == document &&
        known.snapshot == snapshot &&
        (known.graphFile == null || identical(known.graphFile, graph)) &&
        (known.ran || known.changes == session.changes)) {
      return known.ran;
    }
    final shown = sessionGraphOf(
      session,
      documents: outcomes,
      graphFile: graph,
    );
    final id = functionIdIn(shown.graph, function);
    final ran =
        id != null && ranIn(session, placesOfSession(session, shown.graph), id);
    _ranOf[key] = (
      document: document,
      snapshot: snapshot,
      graphFile: shown.noSnapshot ? graph : null,
      changes: session.changes,
      ran: ran,
    );
    return ran;
  }

  /// The id the main graph has in [session] (`functionIdIn`) when the
  /// session is a parent's — of a graph that calls it —, which its canvas
  /// draws (`sessionCanvas`); `null` for one of its own, and while no graph
  /// file has been read.
  String? _calledIn(SessionData session) {
    final (graph, main) = (graphFile.graph, mainGraph);
    if (graph == null || main == null || ranAsWorkflow(session, graph, main)) {
      return null;
    }
    final shown = sessionGraphOf(
      session,
      documents: outcomes,
      graphFile: graph,
    ).graph;
    return functionIdIn(shown, main) ?? main.id;
  }

  /// The selected session; `null` for `Current graph`.
  SessionData? get selectedSession {
    final id = selection.sessionId;
    return selection.currentGraph || id == null ? null : feed.session(id);
  }

  /// The sessions column at [now], newest first, the code of each checked
  /// against its graph. Starts reading the snapshot of the last resume of
  /// each that has one, which its code is checked against: it comes as a
  /// change. Only resumes on other code write one, so there are few.
  List<SessionSummary> sessions(DateTime now) {
    final key = _key(now);
    if (key != _sessionsKey) {
      final listed = workflowSessions;
      for (final session in listed) {
        outcomes.load(session.id, [?snapshotDocumentOf(session)]);
      }
      _sessions = List.unmodifiable(
        sessionSummaries(
          listed,
          now,
          codeOf: (session) => sessionGraphOf(
            session,
            documents: outcomes,
            graphFile: graphFile.graph,
          ).code,
          fromOf: (session) =>
              _calledIn(session) == null ? null : session.session.workflow,
        ),
      );
      _sessionsKey = key;
    }
    return _sessions;
  }

  /// The selected session at [now]; `null` for `Current graph`. Starts
  /// reading its snapshot: it comes as a change.
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
            effectId: selection.effectId,
            levels: canvas.ofSession ? canvas.levels : const [],
            places: canvas.ofSession ? canvas.places : null,
            calledGraph: canvas.ofSession ? canvas.calledGraph : null,
            frames: canvas.ofSession ? canvas.frames : const [],
            openRuns: {..._openRuns},
          );
    _viewKey = key;
    return _view;
  }

  /// The graph on the canvas. Starts reading the selected session's
  /// snapshot: it comes as a change.
  CanvasGraph get canvas {
    if (_canvasKey == _changes) return _canvas!;
    final session = _readSelected();
    final graph = graphFile.graph;
    final canvas = session == null
        ? fileCanvas(
            file: graphFile.file,
            graph: graph,
            workflowId: mainGraph?.id,
            path: _path,
            expansions: _expansions,
            error: graphFile.error,
            fileMissing: graphFile.fileMissing,
            freshness: freshness.freshness,
          )
        : sessionCanvas(
            session,
            sessionGraphOf(session, documents: outcomes, graphFile: graph),
            calledGraph: _calledIn(session),
            path: _path,
            expansions: _expansions,
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

  /// In a parent's session, the last of the effects of [session] in the
  /// main graph, which the selection follows; `null` otherwise.
  String? _lastShownEffect(SessionData session) {
    final called = _calledIn(session);
    if (called == null) return null;
    final shown = sessionGraphOf(
      session,
      documents: outcomes,
      graphFile: graphFile.graph,
    ).graph;
    return effectsIn(
      session,
      session.state.effects,
      placesOfSession(session, shown),
      called,
    ).lastOrNull?.effectId;
  }

  /// A click on the node [nodeId] of the body drawn — or of the body of the
  /// frame drawn in place at [path]: selects the last of the session's
  /// effects on it or in it; nothing without one, and for `Current graph`.
  void clickNode(String nodeId, {List<Opened>? path}) {
    final session = selectedSession;
    final node = _bodyAt(path)?.node(nodeId);
    if (session == null || node == null || !canvas.ofSession) return;
    final last = session.state.effects
        .where((s) => canvas.places.isIn(session.effects[s.effectId], node))
        .lastOrNull;
    if (last != null) selection.selectEffect(session, last.effectId);
  }

  /// The body drawn, or that of the frame drawn in place at [path].
  GraphBody? _bodyAt(List<Opened>? path) {
    if (path == null) return canvas.body;
    final key = levelKey(path);
    return allFrames(canvas.frames)
        .where((frame) => levelKey(frame.path) == key)
        .firstOrNull
        ?.level
        .body;
  }

  /// The visit the effect details window opens on for a double click on the
  /// effect node [node]: its last effect; `null` when it has none, and for
  /// `Current graph`.
  Visit? visitToOpen(EffectNode node) {
    final session = selectedSession;
    if (session == null || !canvas.ofSession) return null;
    return visits.visitToOpen(
      session,
      session.state.effects,
      canvas.places,
      node,
    );
  }

  /// Selects the effect [effectId] of the selected session, a visit the effect
  /// details window shows, so that the canvas and `Logs` are on it.
  void showVisit(String effectId) => selectEffect(effectId);

  /// The effect details window on the effect [effectId] of the selected
  /// session, among the effects `Logs` show, at [now]; on the effect node
  /// [node] alone without an effect.
  VisitDetails detailsOf(EffectNode? node, String? effectId, DateTime now) {
    final view = canvas.ofSession ? sessionView(now) : null;
    // The effects `Logs` show, unless the effect is not one of them: all the
    // session's.
    final logs = view?.logsEffects;
    final effects = logs != null && logs.any((s) => s.effectId == effectId)
        ? logs
        : view?.effects;
    return visitDetails(
      session: effects == null ? null : selectedSession,
      effects: effects ?? const [],
      places: canvas.places,
      effectId: effectId,
      node: node,
      now: now,
    );
  }

  /// Selects the effect [effectId] of the selected session.
  void selectEffect(String effectId) {
    final session = selectedSession;
    if (session != null) selection.selectEffect(session, effectId);
  }

  /// Opens the run of a call [key] in `Logs` (`RunRow.key`), or closes it
  /// when it is open.
  void toggleRun(String key) {
    if (!_openRuns.remove(key)) _openRuns.add(key);
    _changed();
  }

  void _fed() {
    _feedSelection();
    _changed();
  }

  /// Selects [_wantedSession] once the feed has it and the graph file is
  /// read.
  void _openWanted() {
    final id = _wantedSession;
    final session = id == null ? null : feed.session(id);
    if (graphFile.graph == null || session == null) return;
    _wantedSession = null;
    selection.showSession(session);
  }

  void _outcomesRead() {
    // A snapshot read tells whether the main graph ran in its session.
    _feedSelection();
    _changed();
  }

  void _graphFileChanged() {
    final drawn = _canvas;
    // Which sessions are the workflow's may have changed.
    _feedSelection();
    _changed();
    if (!identical(graphFile.graph, _graphRead)) {
      _graphRead = graphFile.graph;
      if (drawn != null) _carryOver(drawn, canvas);
    }
  }

  /// Takes the levels opened and the nodes expanded on [before], the graph
  /// drawn before the graph file was written again, to the same nodes of
  /// [after], the graph drawn now: its nodes may be numbered anew. A level
  /// whose node is gone closes, with those under it, and opens again once a
  /// graph file written later has the node back; an expanded node that is
  /// gone collapses. Nothing changes while the graph drawn is the same — a
  /// session's snapshot —; another workflow drawn starts at its top.
  void _carryOver(CanvasGraph before, CanvasGraph after) {
    final (was, wasFile) = (before.workflow, before.file);
    final (now, nowFile) = (after.workflow, after.file);
    if (identical(wasFile, nowFile) && identical(was, now)) return;
    if (was == null ||
        wasFile == null ||
        now == null ||
        nowFile == null ||
        was.id != now.id) {
      _path = const [];
      _wanted = null;
      _expansions.clear();
      _changed();
      return;
    }
    ({List<Opened> path, bool complete}) follow(List<Opened> path) =>
        followPath(
          path,
          before: was,
          beforeFunctions: wasFile.functions,
          after: now,
          afterFunctions: nowFile.functions,
        );
    // A level whose node is gone for a while — an edit half made — opens
    // again once the node is back.
    final wanted = _wanted ?? pathKeys(was, wasFile.functions, _path);
    final opened = pathOfKeys(wanted, now, nowFile.functions);
    _path = opened.path;
    _wanted = opened.complete ? null : wanted;
    _expansions.follow((path) {
      final followed = follow(path);
      return followed.complete ? followed.path : null;
    });
    _changed();
  }

  /// Gives the [selection] the sessions of the main graph. A selected
  /// session that is no longer one of them — the graph file changed which
  /// workflow it ran — gives way as on opening the graph.
  void _feedSelection() {
    _feeding = true;
    _openWanted();
    // Until the session wanted comes, none is selected.
    final sessions = _wantedSession == null
        ? _sessionsToSelect()
        : const <SessionData>[];
    final selected = selection.sessionId;
    if (selected != null && sessions.every((s) => s.id != selected)) {
      selection.reopen();
    }
    selection.update(sessions);
    _feeding = false;
  }

  /// The sessions of the main graph, and the selected session while its
  /// snapshot is being read: whether the main graph ran in a parent's
  /// session resumed with a snapshot is not known until then, and meanwhile
  /// it would give way to the newest of the others — the session the app was
  /// started on too.
  List<SessionData> _sessionsToSelect() {
    final sessions = workflowSessions;
    final selected = selectedSession;
    if (selected == null || sessions.any((s) => s.id == selected.id)) {
      return sessions;
    }
    final document = snapshotDocumentOf(selected);
    final reading =
        document != null &&
        outcomes[document] == null &&
        outcomes.problemOf(document) == null;
    return reading ? [...sessions, selected] : sessions;
  }

  void _selected() {
    // The runs open are the session's.
    if (_runsOf != selection.sessionId) {
      _openRuns.clear();
      _runsOf = selection.sessionId;
    }
    if (!_feeding) _changed();
  }

  void _changed() {
    _changes++;
    notifyListeners();
  }

  /// Stops the [feed]; completes once it has stopped (`SessionFeed.close`).
  /// [dispose] may follow.
  Future<void> close() => feed.close();

  @override
  void dispose() {
    unawaited(_documents.cancel());
    graphFile.removeListener(_graphFileChanged);
    freshness.removeListener(_changed);
    feed.removeListener(_fed);
    outcomes.removeListener(_outcomesRead);
    selection.removeListener(_selected);
    freshness.dispose();
    graphFile.dispose();
    feed.dispose();
    outcomes.dispose();
    selection.dispose();
    super.dispose();
  }
}

/// Whether a parent's session ran a function, and what that was told from:
/// the session's snapshot document and what of it was read, the graph file
/// when the session is shown on it — it has no snapshot —, how many changes
/// the session had.
typedef _Ran = ({
  String? document,
  Outcome? snapshot,
  GraphFile? graphFile,
  int changes,
  bool ran,
});
