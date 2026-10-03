import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_reader/nanoflow_reader.dart';
import 'package:path/path.dart' as p;

import 'body_path.dart';
import 'freshness.dart';
import 'graph_file_source.dart';
import 'outcomes.dart';
import 'selection.dart';
import 'session_feed.dart';
import 'session_view.dart';
import 'step_files.dart';
import 'texts.dart';

/// Something to know of the graph on the canvas, over its top left (spec
/// §9 «Свежесть», «Сессия»; docs/ui-spec.md «Когда что-то не так»).
@immutable
final class GraphNote {
  const GraphNote(
    this.title, {
    this.danger = false,
    this.lines = const [],
    this.text,
  });

  final String title;

  /// Red: the graph file is gone or cannot be read. Otherwise amber.
  final bool danger;

  /// Errors, paths, warnings: one per line.
  final List<String> lines;

  /// What it means, under the [lines].
  final String? text;

  @override
  bool operator ==(Object other) =>
      other is GraphNote &&
      other.title == title &&
      other.danger == danger &&
      listEquals(other.lines, lines) &&
      other.text == text;

  @override
  int get hashCode => Object.hash(title, danger, Object.hashAll(lines), text);

  @override
  String toString() =>
      'GraphNote($title, danger: $danger, lines: $lines, text: $text)';
}

/// What the canvas says for `Current graph` while no graph file has been
/// read.
const noValidGraphYet = 'No valid graph yet';

/// What the canvas says for a session whose snapshot cannot be read.
const unreadableSessionGraph = 'Graph of this session cannot be read';

/// What the canvas says for a graph file without workflows.
const noWorkflows = 'The graph file has no workflows';

/// What the canvas says for a workflow [name] whose graph has no function
/// of it: a workflow the graph file does not have, or a session whose
/// snapshot does not.
String noWorkflowNamed(String name) => 'The graph has no workflow $name';

/// The graph file is gone: the last graph read from it stays.
const fileUnavailable = 'File unavailable';

/// Said under [fileUnavailable]: [fileName] is gone, and what was read of it
/// stays when [graphKept].
String fileUnavailableDetail(String fileName, {required bool graphKept}) =>
    graphKept
    ? '$fileName is gone; the canvas keeps the last graph read from it.'
    : '$fileName is gone.';

/// The graph file [fileName] is not one the app can read.
String fileUnreadable(String fileName) => '$fileName cannot be read';

/// Said under why the graph file cannot be read, over the last graph read.
const lastGraphShown = 'The canvas shows the last graph read from it.';

/// The code next to the graph file is not the one it was read from.
const graphMayNotMatchCode = 'Graph may not match the code';

/// Said under the files that changed.
const changedSinceWritten =
    'The code next to the graph file has changed since it was written.';

/// The session holds no snapshot of the graph file.
const sessionHasNoSnapshot = 'Session has no snapshot';

/// Said under [sessionHasNoSnapshot].
const noSnapshotDetail = 'It is shown on the graph file as it is now.';

/// The code the session ran on is not that of its graph.
const sessionRanOnOtherCode = 'Session ran on other code';

/// Said under [sessionRanOnOtherCode].
const otherCodeDetail =
    'The graph it is shown on was not read from the code it ran on.';

/// The session recorded no hash of its code.
const sessionCodeNotChecked = 'Session code not checked';

/// Said under [sessionCodeNotChecked].
const notCheckedDetail = 'The session recorded no hash of the code it ran on.';

/// The chosen workflow [workflow] is not in the graph file [fileName]: its
/// sessions ran it, the file does not have it.
String workflowNotInFile(String workflow, String fileName) =>
    'Workflow $workflow is not in $fileName';

/// Said under [workflowNotInFile].
const graphFileMayBeStale =
    'The graph file may be stale: run describe to write it again.';

/// Said under the workflows that sessions ran and the graph file does not
/// have.
const notInGraphFileDetail =
    'The graph file may be stale: run describe to write it again. '
    'Choose such a workflow to see its sessions.';

/// The graph the canvas shows (spec §9 «Граф», «Сессия»): a workflow of the
/// graph file for `Current graph`, the session's own graph for a session;
/// one level of it at a time.
final class CanvasGraph {
  CanvasGraph._({
    required this.file,
    required this.workflow,
    required this.ofSession,
    required List<Opened> path,
    this.placeholder,
    this.notes = const [],
  }) : levels = workflow == null
           ? const []
           : List.unmodifiable(bodyLevels(workflow, file!.functions, path));

  /// The graph file whose functions the canvas draws: the graph file, or
  /// the session's snapshot of it; `null` when there is none to draw.
  final GraphFile? file;

  /// The workflow whose body is the top level of the canvas; `null` when
  /// there is none to draw.
  final GraphFunction? workflow;

  /// Whether the graph is the selected session's own: then the session's
  /// steps go on it. For `Current graph` they do not.
  final bool ofSession;

  /// What the canvas says instead of a graph: [noValidGraphYet],
  /// [noWorkflows], [unreadableSessionGraph], [noWorkflowNamed].
  final String? placeholder;

  /// What to know of the graph, over the canvas.
  final List<GraphNote> notes;

  /// The levels down to the body drawn: the [workflow]'s, then those opened
  /// in it as far as the graph has them (`bodyLevels`); none without a
  /// [workflow].
  final List<BodyLevel> levels;

  /// The body drawn: that of the last of the [levels].
  GraphBody? get body => levels.lastOrNull?.body;

  /// The levels opened under the [workflow]'s body, as far as the graph has
  /// them.
  List<Opened> get path => [for (final level in levels.skip(1)) level.opened!];
}

/// The canvas of `Current graph`: the workflow [workflowId] (a
/// `WorkflowChoice.id`) of [graph], the graph file [file] last read, down
/// [path]; noted when the file is gone, its latest [error], its
/// [freshness], its warnings, then [extraNotes] ([workflowNotes]).
CanvasGraph fileCanvas({
  required String file,
  required GraphFile? graph,
  required String? workflowId,
  List<Opened> path = const [],
  String? error,
  bool fileMissing = false,
  Freshness? freshness,
  List<GraphNote> extraNotes = const [],
}) {
  final name = p.basename(file);
  final workflow = graph?.functions[workflowId];
  final warnings = graph?.warnings ?? const [];
  return CanvasGraph._(
    file: graph,
    workflow: workflow,
    ofSession: false,
    path: path,
    placeholder: graph == null
        ? noValidGraphYet
        : workflow != null
        ? null
        : workflowId == null
        ? noWorkflows
        : noWorkflowNamed(workflowId),
    notes: List.unmodifiable([
      if (fileMissing)
        GraphNote(
          fileUnavailable,
          danger: true,
          text: fileUnavailableDetail(name, graphKept: graph != null),
        ),
      if (error != null)
        GraphNote(
          fileUnreadable(name),
          danger: true,
          lines: [error],
          text: graph == null ? null : lastGraphShown,
        ),
      if (freshness != null && freshness.stale)
        GraphNote(
          graphMayNotMatchCode,
          lines: freshness.changed,
          text: changedSinceWritten,
        ),
      if (warnings.isNotEmpty)
        GraphNote(
          '${count(warnings.length, 'warning')} in $name',
          lines: [
            for (final GraphWarning(:place, :message) in warnings)
              place == null ? message : '$place  $message',
          ],
        ),
      ...extraNotes,
    ]),
  );
}

/// The canvas of [session], shown on [graph]: its workflow on it, down
/// [path]; noted when the session has no snapshot, when its code is not
/// that of the graph or was not recorded, then [extraNotes]
/// ([workflowNotes]).
CanvasGraph sessionCanvas(
  SessionData session,
  SessionGraph graph, {
  List<Opened> path = const [],
  List<GraphNote> extraNotes = const [],
}) {
  final file = graph.graph;
  final name = session.session.workflow;
  final workflow = file?.workflowNamed(name);
  return CanvasGraph._(
    file: file,
    workflow: workflow,
    ofSession: true,
    path: path,
    placeholder: graph.unreadable
        ? unreadableSessionGraph
        : file == null
        ? (graph.noSnapshot ? noValidGraphYet : null)
        : workflow == null
        ? noWorkflowNamed(name)
        : null,
    notes: List.unmodifiable([
      if (graph.noSnapshot)
        const GraphNote(sessionHasNoSnapshot, text: noSnapshotDetail),
      if (graph.code == CodeCheck.otherCode)
        const GraphNote(sessionRanOnOtherCode, text: otherCodeDetail),
      if (graph.code == CodeCheck.notChecked)
        const GraphNote(sessionCodeNotChecked, text: notCheckedDetail),
      ...extraNotes,
    ]),
  );
}

/// What to know of the workflows of the graph file [file], over any canvas:
/// that the chosen [workflow] is not in the file; else, how many sessions
/// ran workflows the file does not have ([notInGraph], by name), which are
/// otherwise easy to miss: only the workflow picker lists them.
List<GraphNote> workflowNotes({
  required String file,
  required WorkflowChoice? workflow,
  required Map<String, int> notInGraph,
}) {
  final name = p.basename(file);
  if (workflow != null && !workflow.inGraphFile) {
    return [
      GraphNote(
        workflowNotInFile(workflow.name, name),
        text: graphFileMayBeStale,
      ),
    ];
  }
  if (notInGraph.isEmpty) return const [];
  final sessions = notInGraph.values.fold(0, (sum, n) => sum + n);
  final workflows = notInGraph.length == 1
      ? 'a workflow'
      : '${notInGraph.length} workflows';
  return [
    GraphNote(
      '${count(sessions, 'session')} of $workflows not in $name',
      lines: [...notInGraph.keys],
      text: notInGraphFileDetail,
    ),
  ];
}

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
  }) : selection = Selection(now: now) {
    graphFile.addListener(_graphFileChanged);
    freshness.addListener(_changed);
    feed.addListener(_fed);
    outcomes.addListener(_changed);
    selection.addListener(_selected);
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

  /// The sessions column at [now], newest first.
  List<SessionSummary> sessions(DateTime now) {
    final key = _key(now);
    if (key != _sessionsKey) {
      _sessions = List.unmodifiable(sessionSummaries(workflowSessions, now));
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
            stepId: selection.stepId,
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
