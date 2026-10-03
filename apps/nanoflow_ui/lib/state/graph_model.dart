import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_reader/nanoflow_reader.dart';
import 'package:path/path.dart' as p;

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

/// What the canvas says for a session whose graph has no function of its
/// workflow [name].
String noWorkflowNamed(String name) => 'The graph has no workflow $name';

/// The graph file is gone: the last graph read from it stays.
const fileUnavailable = 'File unavailable';

/// Said under [fileUnavailable]: what was read of [fileName] stays.
String fileUnavailableDetail(String fileName) =>
    '$fileName is gone; the canvas keeps the last graph read from it.';

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

/// The graph the canvas shows (spec §9 «Граф», «Сессия»): a workflow of the
/// graph file for `Current graph`, the session's own graph for a session.
final class CanvasGraph {
  const CanvasGraph._({
    required this.file,
    required this.workflow,
    required this.ofSession,
    this.placeholder,
    this.notes = const [],
  });

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
}

/// The canvas of `Current graph`: the workflow [workflowId] of [graph], the
/// graph file [file] last read; noted when the file is gone, its latest
/// [error], its [freshness] and its warnings.
CanvasGraph fileCanvas({
  required String file,
  required GraphFile? graph,
  required String? workflowId,
  String? error,
  bool fileMissing = false,
  Freshness? freshness,
}) {
  final name = p.basename(file);
  final workflow = graph?.functions[workflowId];
  final warnings = graph?.warnings ?? const [];
  return CanvasGraph._(
    file: graph,
    workflow: workflow,
    ofSession: false,
    placeholder: graph == null
        ? noValidGraphYet
        : workflow == null
        ? noWorkflows
        : null,
    notes: List.unmodifiable([
      if (fileMissing)
        GraphNote(
          fileUnavailable,
          danger: true,
          text: fileUnavailableDetail(name),
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
    ]),
  );
}

/// The canvas of [session], shown on [graph]: its workflow on it; noted
/// when the session has no snapshot, and when its code is not that of the
/// graph or was not recorded.
CanvasGraph sessionCanvas(SessionData session, SessionGraph graph) {
  final file = graph.graph;
  final name = session.session.workflow;
  final workflow = file?.workflowNamed(name);
  return CanvasGraph._(
    file: file,
    workflow: workflow,
    ofSession: true,
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
    ]),
  );
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

  /// The workflow the user chose; [workflow] falls back to the first.
  String? _workflowId;

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

  /// The workflows of the graph file, in its order; none while no graph file
  /// has been read.
  List<GraphFunction> get workflows {
    final graph = graphFile.graph;
    if (graph == null) return const [];
    return [for (final id in graph.workflows) ?graph.functions[id]];
  }

  /// The selected workflow: the one chosen while the graph file has it,
  /// else its first; `null` without workflows.
  GraphFunction? get workflow {
    final all = workflows;
    return all.where((w) => w.id == _workflowId).firstOrNull ?? all.firstOrNull;
  }

  /// Selects the workflow [id], and opens its sessions as on opening the
  /// graph: its newest session started before now is selected.
  void selectWorkflow(String id) {
    if (id == workflow?.id) return;
    _workflowId = id;
    selection.reopen();
    _feedSelection();
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
    final canvas = session == null
        ? fileCanvas(
            file: graphFile.file,
            graph: graphFile.graph,
            workflowId: workflow?.id,
            error: graphFile.error,
            fileMissing: graphFile.fileMissing,
            freshness: freshness.freshness,
          )
        : sessionCanvas(
            session,
            sessionGraphOf(
              session,
              documents: outcomes,
              graphFile: graphFile.graph,
            ),
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

  void _feedSelection() {
    _feeding = true;
    selection.update(workflowSessions);
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
