// migrated in Task 12: still on the old model (runs, the README graph,
// GraphSource); it does not compile until then.
/// What a session puts on its graph: node states, run markers, visit and
/// arrow counters, the selected run's path (docs/ui-spec.md «Граф»). Pure.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import '../layout/layout_graph.dart' show counterText;
import 'outcomes.dart';
import 'runs.dart';
import 'session_feed.dart';
import 'texts.dart' as texts show shortId;

/// A node's state over all runs of a session; a later value wins over an
/// earlier one (ui-spec «Граф»).
enum NodeState {
  /// No steps.
  notVisited,

  /// Finished steps.
  visited,

  /// A step without `step-finished`.
  running,

  /// A run failed on a step of the node.
  failed,
}

/// An exit of a node: its index in the node's exits.
typedef ExitKey = ({String node, int exit});

/// An arrow: from an exit of a node to a node of its target.
typedef ArrowKey = ({String from, int exit, String to});

/// A run's id over the tile of the node it is on.
final class RunMarker {
  RunMarker(this.runId, this.phase);

  final String runId;

  String get shortId => texts.shortId(runId);

  /// The marker is drawn in the color of the run's state.
  final RunPhase phase;
}

/// What a session puts on its graph: node states, run markers, visit and
/// arrow counters.
final class GraphMarks {
  GraphMarks._(this._states, this._visits, this.passes, this._markers);

  /// The marks of every run of [session]. A fork step counts once its
  /// outcome is known through [outcomes].
  factory GraphMarks.of(SessionData session, KnownOutcomes outcomes) {
    final graph = session.graph;
    final states = <String, NodeState>{};
    final visits = <String, int>{};
    final passes = <ExitKey, int>{};
    final markers = <String, List<RunMarker>>{};
    for (final run in runsInOrder(session)) {
      for (final step in run.state.steps) {
        visits.update(step.node, (n) => n + 1, ifAbsent: () => 1);
        final state = switch (step.status) {
          StepStatus.failed => NodeState.failed,
          StepStatus.running => NodeState.running,
          StepStatus.finished => NodeState.visited,
        };
        final known = states[step.node];
        if (known == null || state.index > known.index) {
          states[step.node] = state;
        }
        final exit = _exitTaken(graph, run, step, outcomes);
        if (exit != null) passes.update(exit, (n) => n + 1, ifAbsent: () => 1);
      }
      final phase = phaseOf(run);
      final node = run.state.steps.lastOrNull?.node ?? run.started?.node;
      if (phase != RunPhase.split && node != null) {
        (markers[node] ??= []).add(RunMarker(run.id, phase));
      }
    }
    return GraphMarks._(states, visits, Map.unmodifiable(passes), {
      for (final MapEntry(:key, :value) in markers.entries)
        key: List.unmodifiable(value),
    });
  }

  final Map<String, NodeState> _states;
  final Map<String, int> _visits;
  final Map<String, List<RunMarker>> _markers;

  /// How many times runs went through each exit; exits never gone through
  /// are not here.
  final Map<ExitKey, int> passes;

  NodeState stateOf(String node) => _states[node] ?? NodeState.notVisited;

  /// How many steps the node has had.
  int visitsOf(String node) => _visits[node] ?? 0;

  /// `2×` over a node entered more than once; `null` otherwise.
  String? visitText(String node) {
    final visits = visitsOf(node);
    return visits > 1 ? counterText(visits) : null;
  }

  int passesOf(String node, int exit) => passes[(node: node, exit: exit)] ?? 0;

  /// Whether a run went through the exit: arrows no run took are darker.
  bool isTaken(String node, int exit) => passesOf(node, exit) > 0;

  /// `1×` on the arrows of an exit runs went through; `null` otherwise.
  String? counterOf(String node, int exit) {
    final passes = passesOf(node, exit);
    return passes > 0 ? counterText(passes) : null;
  }

  /// The runs on [node], in the order they were created: every run but those
  /// that split, on the node of its last step; a run not started, on its
  /// start node.
  List<RunMarker> markersOn(String node) => _markers[node] ?? const [];
}

/// The exit [step] of [run] went through: a worker's `then`, the exit a
/// fork's outcome chose. `null` when it went through none (yet): it runs,
/// its run failed on it, its exit code is not 0, its outcome is not known, or
/// its node has no exit for it.
ExitKey? _exitTaken(
  Graph? graph,
  RunData run,
  StepState step,
  KnownOutcomes outcomes,
) {
  if (step.status != StepStatus.finished || step.exitCode != 0) return null;
  switch (graph?.nodes[step.node]) {
    case WorkerNode(:final then):
      return then == null ? null : (node: step.node, exit: 0);
    case final ForkNode fork:
      final outcome = stepOutcome(run, step, outcomes);
      if (outcome == null) return null;
      return switch (fork.route(outcome.value)) {
        RouteTo(:final exit) => (
          node: step.node,
          exit: fork.exits.indexOf(exit),
        ),
        RouteEnd() || RouteMissing() => null,
      };
    case null:
      return null;
  }
}

/// The way a run went: drawn in the accent color.
final class RunPath {
  RunPath._(this.exits, this.arrows, this.inputs);

  /// The exits its steps went through.
  final Set<ExitKey> exits;

  /// The arrows from those exits into the nodes of the steps after them.
  final Set<ArrowKey> arrows;

  /// The nodes entered by an arrow: their input bars.
  final Set<String> inputs;
}

/// The path of the run [runId]: the exits its steps, inherited ones too, went
/// through, the arrows on to the next step, and the nodes they entered.
/// [steps] are the run's [stepsOfRun], when already at hand.
RunPath pathOf(
  SessionData session,
  String runId,
  KnownOutcomes outcomes, {
  List<RunStep>? steps,
}) {
  steps ??= stepsOfRun(session, runId);
  final graph = session.graph;
  final nodes = [for (final step in steps) step.node];
  final run = session.runs[runId];
  // A run not started yet has been sent to its start node.
  final start = run?.started?.node;
  if (run != null && run.state.steps.isEmpty && start != null) {
    if (run.run.parentId != null) nodes.add(start);
  }
  final exits = <ExitKey>{};
  final arrows = <ArrowKey>{};
  for (var i = 0; i < steps.length; i++) {
    final exit = _exitTaken(graph, steps[i].run, steps[i].state, outcomes);
    if (exit == null) continue;
    exits.add(exit);
    if (i + 1 >= nodes.length) continue;
    final target = graph!.nodes[exit.node]!.exits[exit.exit].target;
    if (target.names.contains(nodes[i + 1])) {
      arrows.add((from: exit.node, exit: exit.exit, to: nodes[i + 1]));
    }
  }
  return RunPath._(
    Set.unmodifiable(exits),
    Set.unmodifiable(arrows),
    Set.unmodifiable(nodes.skip(1)),
  );
}
