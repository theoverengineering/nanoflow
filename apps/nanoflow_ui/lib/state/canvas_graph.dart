/// The graph the canvas of a graph screen shows: a workflow of the graph
/// file, or a session's own graph, one level at a time, and what to know
/// of it over the canvas (spec §9 «Граф», «Свежесть», «Сессия»). Pure.
library;

import 'package:flutter/foundation.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import 'body_path.dart';
import 'effect_places.dart';
import 'freshness.dart';
import 'in_place.dart';
import 'session_feed.dart';
import 'session_view.dart';
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

/// [effects] effects of the session ran where the graph has no effect:
/// `2 effects not on the graph`.
String notOnGraphTitle(int effects) =>
    '${count(effects, 'effect')} not on the graph';

/// The most effects the note of those not on the graph lists; `Logs` marks
/// each of them.
const notOnGraphLines = 5;

/// Said under the effects not on the graph.
const notOnGraphDetail =
    'They match no effect on the graph: the code may differ from the one it '
    'was read from.';

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
    Expansions? expansions,
    EffectPlaces? places,
    this.placeholder,
    this.notes = const [],
  }) : levels = workflow == null
           ? const []
           : List.unmodifiable(bodyLevels(workflow, file!.functions, path)),
       places =
           places ?? EffectPlaces.of(workflow, file?.functions ?? const {}) {
    frames = expansions == null || levels.isEmpty
        ? const []
        : List.unmodifiable(inPlaceFrames(levels, file!.functions, expansions));
  }

  /// The graph file whose functions the canvas draws: the graph file, or
  /// the session's snapshot of it; `null` when there is none to draw.
  final GraphFile? file;

  /// The workflow whose body is the top level of the canvas; `null` when
  /// there is none to draw.
  final GraphFunction? workflow;

  /// Whether the graph is the selected session's own: then the session's
  /// effects go on it. For `Current graph` they do not.
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

  /// The nodes of the [body] drawn expanded in place, and those in them
  /// (decision 6).
  late final List<InPlaceFrame> frames;

  /// The places of the effect nodes of the [workflow]: which nodes a
  /// session's effects are on.
  final EffectPlaces places;

  /// The levels opened under the [workflow]'s body, as far as the graph has
  /// them.
  List<Opened> get path => [for (final level in levels.skip(1)) level.opened!];
}

/// The canvas of `Current graph`: the workflow [workflowId] (a
/// `WorkflowChoice.id`) of [graph], the graph file [file] last read, down
/// [path], the nodes [expansions] has expanded in place; noted when the
/// file is gone, its latest [error], its [freshness], its warnings, then
/// [extraNotes] ([workflowNotes]).
CanvasGraph fileCanvas({
  required String file,
  required GraphFile? graph,
  required String? workflowId,
  List<Opened> path = const [],
  Expansions? expansions,
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
    expansions: expansions,
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
/// [path], the nodes [expansions] has expanded in place; noted when the
/// session has no snapshot, when its code is not that of the graph or was
/// not recorded, then [extraNotes] ([workflowNotes]).
CanvasGraph sessionCanvas(
  SessionData session,
  SessionGraph graph, {
  List<Opened> path = const [],
  Expansions? expansions,
  List<GraphNote> extraNotes = const [],
}) {
  final file = graph.graph;
  final name = session.session.workflow;
  final workflow = file?.workflowNamed(name);
  final places = EffectPlaces.of(workflow, file?.functions ?? const {});
  // Without a workflow there is no graph to put the effects on: the canvas
  // says so instead.
  final offGraph = workflow == null
      ? const <Effect>[]
      : effectsNotOnGraph(session.effectsInOrder, places);
  return CanvasGraph._(
    file: file,
    workflow: workflow,
    ofSession: true,
    path: path,
    expansions: expansions,
    places: places,
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
      if (offGraph.isNotEmpty)
        GraphNote(
          notOnGraphTitle(offGraph.length),
          lines: [
            for (final effect in offGraph.take(notOnGraphLines))
              '${effect.name}  ${effect.place ?? 'no place'}',
            if (offGraph.length > notOnGraphLines)
              'and ${offGraph.length - notOnGraphLines} more',
          ],
          text: notOnGraphDetail,
        ),
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
