import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_reader/nanoflow_reader.dart';
import 'package:path/path.dart' as p;

import 'body_path.dart';
import 'called_graph.dart';
import 'canvas_graph.dart';
import 'copies.dart';
import 'copy_choices.dart' as choices show hintOf;
import 'copy_choices.dart' show CopyChoices, hintDocuments;
import 'effect_files.dart';
import 'freshness.dart';
import 'graph_file_source.dart';
import 'in_place.dart';
import 'node_keys.dart';
import 'outcomes.dart';
import 'selection.dart';
import 'session_feed.dart';
import 'session_view.dart';
import 'visit_details.dart';
import 'visits.dart' as visits show visitToOpen;
import 'visits.dart' show Visit;

export 'canvas_graph.dart';

/// The state of one graph screen: the graph file and how it stands against
/// the code, the sessions of its selected workflow — or of the function the
/// workflows call opened as the main graph, its called graph —, what is
/// selected, the levels opened and the nodes expanded in place, the
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
    DateTime Function()? now,
  }) : selection = Selection(now: now),
       _now = now ?? DateTime.now {
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

  /// The logs and documents of effects, read when the effect details show them.
  final EffectFiles files;

  late final StreamSubscription<DocumentAdded> _documents;

  /// The workflow the user chose, by its id and its name: [workflow] finds
  /// it by its name when its id has changed, as when describe writes a
  /// workflow its sessions ran to the graph file; it falls back to the
  /// first.
  ({String id, String name})? _chosen;

  /// The id of the function the workflows call opened as the main graph
  /// (open-as-graph design): it is drawn instead of the workflow chosen
  /// while the graph file has it. `null` while none is open.
  String? _called;

  /// Whether each session ran the called graph opened, by the session's
  /// id, with what that was told from: the session as it was, its snapshot
  /// read, the graph file, the function (`_ranCalled`).
  final Map<String, _RanCalled> _ranCalledOf = {};

  /// The levels opened under the workflow's body: the canvas goes down them
  /// as far as the graph it draws has them.
  List<Opened> _path = const [];

  /// The nodes of the levels opened last, by their keys ([pathKeys]), while
  /// a graph file written again has not all of them: [_path] goes down them
  /// again as far as the graph file has them. `null` while [_path] has them
  /// all.
  List<(String, String?)>? _wanted;

  /// The time, for what is derived at a moment.
  final DateTime Function() _now;

  /// The copies chosen in the copies frames of the selected session.
  final _copies = CopyChoices();

  /// The nodes expanded in place: they stay for any session of the
  /// workflow, go for another workflow, and follow their nodes into a graph
  /// file written again ([_carryOver]).
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

  /// The workflows to choose from: the called graph open first, unless it
  /// is one of them; the graph file's in its order, then those sessions ran
  /// that it does not have (`workflowChoices`); none while no graph file
  /// has been read.
  List<WorkflowChoice> get workflows {
    final graph = graphFile.graph;
    return graph == null
        ? const []
        : workflowChoices(graph, feed.sessions.values, called: _called);
  }

  /// The selected workflow: the called graph while one is open; else the
  /// one chosen while it is listed, by its id or else its name; else the
  /// first; `null` without workflows.
  WorkflowChoice? get workflow {
    final all = workflows;
    final chosen = _chosen;
    if (calledGraph != null) return all.firstWhere((w) => w.id == _called);
    return all.where((w) => w.id == chosen?.id).firstOrNull ??
        all.where((w) => w.name == chosen?.name).firstOrNull ??
        all.firstOrNull;
  }

  /// The function the workflows call opened as the main graph, as the
  /// graph file has it; `null` while none is open, or the graph file does
  /// not have it.
  GraphFunction? get calledGraph => graphFile.graph?.functions[_called];

  /// Selects the workflow [id] (a [WorkflowChoice.id]), drawn from its top
  /// level; the called graph open goes, but for itself chosen. Another
  /// workflow's sessions open as on opening the graph: its newest session
  /// started before now is selected.
  void selectWorkflow(String id) {
    final choice = workflows.where((w) => w.id == id).firstOrNull;
    if (choice == null) return;
    _path = const [];
    _wanted = null;
    if (!choice.called) {
      final drawn = workflow?.id;
      final wasCalled = calledGraph != null;
      _called = null;
      _chosen = (id: choice.id, name: choice.name);
      if (id != drawn) _expansions.clear();
      if (id != drawn || wasCalled) _mainGraphChanged();
    }
    _changed();
  }

  /// Opens the function [functionId] of the graph file as the main graph
  /// (open-as-graph design §3): drawn from its top, its sessions listed —
  /// those of its own and its parents' ([workflowSessions]). The levels
  /// opened and the nodes expanded go, as for another workflow; the
  /// selected session stays while the function ran in it. Nothing opens
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

  /// Gives the [selection] the sessions of the main graph drawn now: the
  /// selected session stays while it is one of them; else, and for
  /// `Current graph`, they open as on opening the graph.
  void _mainGraphChanged() {
    final selected = selection.sessionId;
    if (selection.currentGraph ||
        workflowSessions.every((s) => s.id != selected)) {
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

  /// The sessions of the selected workflow as the feed has them: every
  /// session while no graph file has been read. With a called graph open,
  /// those it ran in (open-as-graph design §4): its own, and those of the
  /// workflows that call it in which an effect is in its body — by their
  /// places on their snapshots, which start being read: they come as a
  /// change.
  List<SessionData> get workflowSessions {
    final graph = graphFile.graph;
    final called = calledGraph;
    if (graph == null || called == null) {
      return sessionsOfWorkflow(feed.sessions.values, graph, workflow?.id);
    }
    return [
      for (final session in feed.sessions.values)
        if (ranAsWorkflow(session, graph, called) ||
            _ranCalled(session, graph, called.id))
          session,
    ];
  }

  /// Whether the called graph [functionId] ran in [session], a session of
  /// another workflow, on its snapshot (`ranIn`): worked out again only
  /// once the session, its snapshot or the graph file has changed. Starts
  /// reading the snapshot.
  bool _ranCalled(SessionData session, GraphFile graph, String functionId) {
    final document = snapshotDocumentOf(session);
    if (document != null) outcomes.load(session.id, [document]);
    final snapshot = document == null ? null : outcomes[document];
    final known = _ranCalledOf[session.id];
    if (known != null &&
        known.changes == session.changes &&
        known.snapshot == snapshot &&
        identical(known.graph, graph) &&
        known.function == functionId) {
      return known.ran;
    }
    final shown = sessionGraphOf(
      session,
      documents: outcomes,
      graphFile: graph,
    ).graph;
    final ran = ranIn(session, placesOfSession(session, shown), functionId);
    _ranCalledOf[session.id] = (
      changes: session.changes,
      snapshot: snapshot,
      graph: graph,
      function: functionId,
      ran: ran,
    );
    return ran;
  }

  /// The id of the called graph open when [session] is a parent's — of a
  /// workflow that calls it —, which its canvas draws (`sessionCanvas`);
  /// `null` for any other session, and while none is open.
  String? _calledIn(SessionData session) {
    final (graph, called) = (graphFile.graph, calledGraph);
    return graph == null ||
            called == null ||
            ranAsWorkflow(session, graph, called)
        ? null
        : called.id;
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
  /// reading its snapshot, and the outputs of the first effects of the
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
            effectId: selection.effectId,
            levels: canvas.ofSession ? canvas.levels : const [],
            places: canvas.ofSession ? canvas.places : null,
            calledGraph: canvas.ofSession ? canvas.calledGraph : null,
            copies: _copies.on(canvas.path),
            frames: canvas.ofSession ? canvas.frames : const [],
            copiesIn: _copies.on,
            follow: _followed(session)?.path,
          );
    // What the copies' first effects gave tells them apart: read it now.
    if (session != null) {
      final view = _view!;
      outcomes.load(session.id, [
        ...hintDocuments(view.shown),
        if (canvas.ofSession)
          for (final frame in allFrames(canvas.frames))
            ...hintDocuments(view.shownAt(frame.path)),
      ]);
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
            expansions: _expansions,
            error: graphFile.error,
            fileMissing: graphFile.fileMissing,
            freshness: freshness.freshness,
            extraNotes: notes,
          )
        : sessionCanvas(
            session,
            sessionGraphOf(session, documents: outcomes, graphFile: graph),
            calledGraph: _calledIn(session),
            path: _path,
            expansions: _expansions,
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

  /// The copies frames of the canvas's levels and the effects they show, of
  /// the selected session on its own graph, as [sessionView] has them at
  /// [now] — in the frame drawn in place at [path] when it is given;
  /// `null` for `Current graph`.
  ShownEffects? _shown(DateTime now, [List<Opened>? path]) =>
      canvas.ofSession ? sessionView(now)?.shownAt(path) : null;

  /// The frame drawn in place whose copy `Logs` follow: of those where a
  /// copy of [session] is chosen, the one chosen last; `null` for none —
  /// `Logs` follow the level drawn.
  InPlaceFrame? _followed(SessionData session) {
    if (!canvas.ofSession) return null;
    final frames = allFrames(canvas.frames).toList();
    final path = _copies.lastChosen(session.id, [
      for (final frame in frames) frame.path,
    ]);
    if (path == null) return null;
    final key = levelKey(path);
    return frames.where((frame) => levelKey(frame.path) == key).firstOrNull;
  }

  /// The frames and effects `Logs` show of [session] as they are now, the
  /// copies chosen as they are now: for what changes them before
  /// [sessionView] can tell.
  ShownEffects? _shownNow(SessionData session) {
    final canvas = this.canvas;
    if (!canvas.ofSession) return null;
    final followed = _followed(session);
    return framesOf(
      followed?.levels ?? canvas.levels,
      places: canvas.places,
      session: session,
      selected: _copies.on(followed?.path ?? canvas.path),
    );
  }

  /// The last of the effects of [session] shown, while copies of it are
  /// chosen: the selection follows the copy shown; in a parent's session,
  /// the last of its effects in the called graph open; `null` otherwise.
  String? _lastShownEffect(SessionData session) {
    if (_copies.anyFor(session.id)) {
      return _shownNow(session)?.effects.lastOrNull?.effectId;
    }
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

  /// Shows the copy [copyId] — the id of its first effect — of the copies
  /// frame at the level [depth] of the canvas, and selects its last effect;
  /// every copy for `null` (decision 11).
  void selectCopy(int depth, String? copyId) =>
      selectCopyAt(canvas.path.take(depth).toList(), copyId);

  /// Shows the copy [copyId] of the copies frame at [path] — a level
  /// opened, or a frame drawn in place: the same choice for both — and
  /// selects its last effect; every copy for `null` (decision 11).
  void selectCopyAt(List<Opened> path, String? copyId) {
    final session = selectedSession;
    final canvas = this.canvas;
    final workflow = canvas.workflow;
    if (session == null || workflow == null) return;
    _copies.choose(session.id, path, path.length, copyId);
    final frame = framesOf(
      bodyLevels(workflow, canvas.file!.functions, path),
      places: canvas.places,
      session: session,
      selected: _copies.on(path),
    ).frames.where((f) => f.depth == path.length).firstOrNull;
    final last = frame?.selected?.effects.lastOrNull;
    if (last != null) selection.selectEffect(session, last.effectId);
    _changed();
  }

  /// What the first effect of [copy] of the selected session gave, to tell
  /// the copy by (`copyHint`); `null` while it is not known: [sessionView]
  /// reads it.
  String? hintOf(Copy copy) => choices.hintOf(copy, outcomes);

  /// A click on the node [nodeId] of the body drawn — or of the body of the
  /// frame drawn in place at [path]: selects the last of the effects shown on
  /// it or in it; nothing without one.
  void clickNode(String nodeId, {List<Opened>? path}) {
    final session = selectedSession;
    final node = _bodyAt(path)?.node(nodeId);
    final shown = _shown(_now(), path);
    if (session == null || node == null || shown == null) return;
    final last = shown.effects
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
  /// effect node [node] — of the frame drawn in place at [path], when given:
  /// its last effect among those shown; `null` when it has none, and for
  /// `Current graph`.
  Visit? visitToOpen(EffectNode node, {List<Opened>? path}) {
    final session = selectedSession;
    final shown = _shown(_now(), path);
    if (session == null || shown == null) return null;
    return visits.visitToOpen(session, shown.effects, canvas.places, node);
  }

  /// Selects the effect [effectId] of the selected session, a visit the effect
  /// details window shows, so that the canvas and `Logs` are on it.
  void showVisit(String effectId) => selectEffect(effectId);

  /// The effect details window on the effect [effectId] of the selected
  /// session, among the effects shown, at [now]; on the effect node [node]
  /// alone without an effect.
  VisitDetails detailsOf(EffectNode? node, String? effectId, DateTime now) {
    final view = canvas.ofSession ? sessionView(now) : null;
    // The effects `Logs` show, unless the effect is not one of them: those of
    // the level drawn.
    final logs = view?.logsShown;
    final shown =
        logs != null && logs.effects.any((s) => s.effectId == effectId)
        ? logs
        : view?.shown;
    return visitDetails(
      session: shown == null ? null : selectedSession,
      effects: shown?.effects ?? const [],
      places: canvas.places,
      effectId: effectId,
      node: node,
      copyOf: view?.copyOf,
      now: now,
    );
  }

  /// Selects the effect [effectId] of the selected session.
  void selectEffect(String effectId) {
    final session = selectedSession;
    if (session != null) selection.selectEffect(session, effectId);
  }

  void _fed() {
    _feedSelection();
    _changed();
  }

  void _outcomesRead() {
    // A snapshot read tells whether the called graph ran in its session.
    if (calledGraph != null) _feedSelection();
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

/// Whether a session ran the called graph opened, and what that was told
/// from: how many changes the session had, its snapshot read, the graph
/// file, the function.
typedef _RanCalled = ({
  int changes,
  Outcome? snapshot,
  GraphFile graph,
  String function,
  bool ran,
});
