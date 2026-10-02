/// What the step details window shows of a visit to a node: the visit among
/// all the visits to the node, how the step went, where its input came from,
/// and the node's description (docs/ui-spec.md «Окно деталей шага»). Pure:
/// the time is passed in.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'schema_labels.dart';
import 'session_feed.dart';
import 'step_details.dart';
import 'texts.dart';
import 'visits.dart';

/// A type of a node's `in` or `out`: its label and its fields.
final class TypeCard {
  const TypeCard(this.label, this.fields);

  /// `#/Change`, `string[]`.
  final String label;

  /// `{ id, path }`; `null` for a type without properties.
  final String? fields;
}

/// A node a way leads to, and whether it is a fork: its icon.
typedef WayTarget = ({String name, bool fork});

/// Where a node sends the run: for an [outcome] of a fork — its key in
/// `then`, `true`, `else` — or after a worker ([outcome] `null`). No
/// [targets]: the run ends.
typedef Way = ({String? outcome, List<WayTarget> targets});

/// A node as the graph describes it.
final class NodeDescription {
  NodeDescription._({
    required this.name,
    required this.fork,
    required this.run,
    required this.input,
    required this.output,
    required List<Way> ways,
  }) : ways = List.unmodifiable(ways);

  /// [node] of [graph].
  factory NodeDescription.of(Node node, Graph graph) {
    TypeCard? card(Object? schema) => schema == null
        ? null
        : TypeCard(typeLabel(schema), fieldSummary(schema, graph.types));
    List<WayTarget> targets(Target? target) => [
      for (final name in target?.names ?? const <String>[])
        (name: name, fork: graph.nodes[name] is ForkNode),
    ];
    return NodeDescription._(
      name: node.name,
      fork: node is ForkNode,
      run: node.run,
      input: card(node.input),
      output: node is WorkerNode ? card(node.output) : null,
      ways: switch (node) {
        WorkerNode(:final then) => [(outcome: null, targets: targets(then))],
        ForkNode(:final exits, :final isIf, :final otherwise) => [
          for (final exit in exits)
            (outcome: exit.label, targets: targets(exit.target)),
          // An if without `else` ends the run on any other outcome; a
          // switch without one fails it, which is no way to go.
          if (isIf && otherwise == null)
            (outcome: 'else', targets: const <WayTarget>[]),
        ],
      },
    );
  }

  final String name;

  final bool fork;

  /// What the node runs: its `command`, or a fork's `decide`.
  final String run;

  /// The title over [run].
  String get runTitle => fork ? 'Decide' : 'Command';

  /// `null` when the node declares no `in`.
  final TypeCard? input;

  /// `null` when the node declares no `out`, and for a fork.
  final TypeCard? output;

  /// A worker's `then`; a fork's outcomes, `else` last — for an if without
  /// `else` too, leading nowhere, as it does.
  final List<Way> ways;
}

/// How the step went, at the top of the window: `exit 0 · 4m 02s`,
/// `running · 2m 14s`, `failed · 0.1s`.
typedef StepResult = ({StepStatus status, String text});

/// A start of the step, as the window lists it: `14:09:20`.
typedef StartText = ({String time, bool interrupted});

/// The facts of the step: `Started`, `Finished`, `Exit code`, `Starts`.
final class StepFacts {
  StepFacts._({
    required this.started,
    required this.finished,
    required this.took,
    required this.exitCode,
    required List<StartText> starts,
  }) : starts = List.unmodifiable(starts);

  /// The first start, to the millisecond: `14:09:20.118`.
  final String started;

  /// `step-finished`, to the millisecond; `null` while the step runs, and
  /// for a step that could not start.
  final String? finished;

  /// `took 4m 02s`; `null` with [finished].
  final String? took;

  /// `null` without `step-finished`.
  final int? exitCode;

  /// Every start; all but the last were interrupted.
  final List<StartText> starts;
}

/// The step details window on the node [node], at its visit of the step
/// [stepId].
final class VisitDetails {
  VisitDetails._({
    required this.node,
    required this.description,
    required List<Visit> visits,
    required this.index,
    this.step,
    this.result,
    this.source,
    this.facts,
    this.error,
  }) : visits = List.unmodifiable(visits);

  final String node;

  /// `null` when the graph has no such node.
  final NodeDescription? description;

  /// Every visit to the node in the session, in order.
  final List<Visit> visits;

  /// Which of [visits] is shown; `null` for the node's description alone.
  final int? index;

  Visit? get visit => switch (index) {
    final i? => visits[i],
    null => null,
  };

  /// `Visit 2 of 2`.
  String? get visitText =>
      index == null ? null : 'Visit ${index! + 1} of ${visits.length}';

  /// The visit before, and the one after.
  Visit? get previous =>
      index != null && index! > 0 ? visits[index! - 1] : null;
  Visit? get next =>
      index != null && index! < visits.length - 1 ? visits[index! + 1] : null;

  /// The step: its input and output documents, its status.
  final StepDetails? step;

  final StepResult? result;

  /// Where the input came from; `null` when that is not known.
  final InputSource? source;

  final StepFacts? facts;

  /// The `run-failed` error, when the run failed on the step.
  final String? error;
}

/// The window on [node] of [graph], at the visit of the step [stepId] of
/// [session] at [now]. Without a [session] (`Current graph`), or a step that
/// is not a visit to [node], it shows the node's description alone.
VisitDetails visitDetails({
  required SessionData? session,
  required Graph? graph,
  required String node,
  required String? stepId,
  required DateTime now,
}) {
  final described = graph?.nodes[node];
  final description = described == null
      ? null
      : NodeDescription.of(described, graph!);
  final visits = session == null ? <Visit>[] : visitsTo(session, node);
  final index = visits.indexWhere((visit) => visit.stepId == stepId);
  if (session == null || index < 0) {
    return VisitDetails._(
      node: node,
      description: description,
      visits: visits,
      index: null,
    );
  }
  final visit = visits[index];
  final run = visit.run;
  final state = visit.state;
  final failed = state.status == StepStatus.failed;
  // A step that could not start fails without `step-finished` (D16).
  final end = state.finishedAt ?? (failed ? run.state.finishedAt : null);
  final took = formatDuration((end ?? now).difference(state.startedAt));
  final code = state.exitCode;
  return VisitDetails._(
    node: node,
    description: description,
    visits: visits,
    index: index,
    step: stepDetails(session, run.id, visit.stepId),
    result: (
      status: state.status,
      text: switch (state.status) {
        StepStatus.running => 'running · $took',
        _ when code == null => 'failed · $took',
        _ => 'exit $code · $took',
      },
    ),
    source: inputSource(session, visit),
    facts: StepFacts._(
      started: clockTimeMillis(state.startedAt),
      finished: state.finishedAt == null
          ? null
          : clockTimeMillis(state.finishedAt!),
      took: state.finishedAt == null ? null : 'took $took',
      exitCode: code,
      starts: [
        for (final start in startsOf(run, visit.stepId))
          (time: clockTime(start.at), interrupted: start.interrupted),
      ],
    ),
    error: failed ? run.state.error : null,
  );
}
