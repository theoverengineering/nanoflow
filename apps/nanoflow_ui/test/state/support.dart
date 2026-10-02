// Sessions written as journals, the way the engine writes them, for the
// tests of what the app derives from them.

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/outcomes.dart';
import 'package:nanoflow_ui/state/session_feed.dart';

/// The README's review graph, as a session holds it.
const reviewGraph = <String, Object?>{
  'start': 'collect',
  'nodes': {
    'collect': {'command': 'nodes/collect/run.sh', 'then': 'is-empty'},
    'is-empty': {
      'decide': 'nodes/is-empty/run.sh',
      'then': 'discard',
      'else': 'inspect',
    },
    'inspect': {'command': 'nodes/inspect/run.sh', 'then': 'verdict'},
    'verdict': {
      'decide': 'nodes/verdict/run.sh',
      'then': {
        'accepted': ['publish', 'notify'],
        'returned': 'fix',
      },
    },
    'fix': {'command': 'nodes/fix/run.sh', 'then': 'inspect'},
    'publish': {'command': 'nodes/publish/run.sh'},
    'discard': {'command': 'nodes/discard/run.sh'},
    'notify': {'command': 'nodes/notify/run.sh'},
  },
};

/// 14:03:11 local time on 2026-09-21: when the mockups' session a1b2 starts.
final DateTime t0 = DateTime(2026, 9, 21, 14, 3, 11).toUtc();

/// [t0] moved on by [seconds], to the millisecond.
DateTime at(num seconds) =>
    t0.add(Duration(milliseconds: (seconds * 1000).round()));

/// A run's journal, written event by event.
final class Journal {
  /// A run that starts at [node] at [startedAt] (seconds after [t0]); no
  /// `run-started` yet when [startedAt] is `null`.
  Journal(
    this.id, {
    this.parent,
    required this.node,
    required num? startedAt,
    this.sessionId = 'a1b2-session',
  }) {
    if (startedAt != null) {
      events.add(RunStarted(runId: id, time: at(startedAt), node: node));
    }
  }

  final String id;
  final String? parent;
  final String node;
  final String sessionId;
  final List<Event> events = [];
  final List<Step> steps = [];

  /// A step of [node] started at [start], again at each of [restarts], and
  /// finished at [end] with [exit] and [output]; running without [end].
  /// Returns its id.
  String step(
    String node,
    num start, {
    num? end,
    int exit = 0,
    String? output,
    List<num> restarts = const [],
  }) {
    final stepId = '${id.substring(0, 4)}-$node-${steps.length}';
    steps.add(
      Step(
        id: stepId,
        runId: id,
        inputId: null,
        outputId: output,
        log: 'command.log',
      ),
    );
    for (final time in [start, ...restarts]) {
      events.add(
        StepStarted(runId: id, time: at(time), stepId: stepId, node: node),
      );
    }
    if (end != null) {
      events.add(
        StepFinished(
          runId: id,
          time: at(end),
          stepId: stepId,
          exitCode: exit,
          outputId: output,
        ),
      );
    }
    return stepId;
  }

  void fail(String stepId, num time, String error) => events.add(
    RunFailed(runId: id, time: at(time), stepId: stepId, error: error),
  );

  void split(num time) => events.add(RunSplit(runId: id, time: at(time)));

  void finish(num time) => events.add(RunFinished(runId: id, time: at(time)));

  RunData get data => RunData(
    Run(id: id, sessionId: sessionId, parentId: parent),
    events: events,
    steps: steps,
  );
}

/// A session of [runs] holding [graph].
SessionData sessionOf(
  List<Journal> runs, {
  String id = 'a1b2-session',
  Map<String, Object?> graph = reviewGraph,
}) => SessionData(
  Session(id: id, graph: graph),
  runs: [for (final run in runs) run.data],
);

/// Outcomes known by document id, and documents that could not be read.
KnownOutcomes outcomesOf(
  Map<String, Object?> values, {
  Map<String, String> failed = const {},
}) => _Outcomes(values, failed);

final class _Outcomes implements KnownOutcomes {
  _Outcomes(this._values, this._failed);

  final Map<String, Object?> _values;
  final Map<String, String> _failed;

  @override
  Outcome? operator [](String documentId) =>
      _values.containsKey(documentId) ? (value: _values[documentId]) : null;

  @override
  String? problemOf(String documentId) => _failed[documentId];
}

/// What app reads for docs/design/graph.png: session a1b2 at 14:15:37.
///
/// Run k7f2 went collect, is-empty (else), inspect, verdict (returned), fix,
/// inspect (started twice), verdict (accepted) and split into c3d4, which
/// finished publish, and e5f6, which runs notify.
final class Mockup {
  Mockup() {
    k7f2.step('collect', 0, end: 149, output: 'change-1');
    k7f2.step('is-empty', 149, end: 150, output: 'is-empty-outcome');
    k7f2.step('inspect', 150, end: 342, output: 'report-1');
    k7f2.step('verdict', 342, end: 342.4, output: 'verdict-outcome-1');
    k7f2.step('fix', 343, end: 369, output: 'change-2');
    k7f2.step('inspect', 369, restarts: [400], end: 611, output: 'report-2');
    k7f2.step('verdict', 611, end: 611.3, output: 'verdict-outcome-2');
    k7f2.split(611.4);
    c3d4.step('publish', 612, end: 640);
    c3d4.finish(640);
    e5f6.step('notify', 612);
  }

  /// 14:15:37: the session has been running for 12m 26s.
  static final DateTime now = at(746);

  final k7f2 = Journal('k7f2-run', node: 'collect', startedAt: 0);
  final c3d4 = Journal(
    'c3d4-run',
    parent: 'k7f2-run',
    node: 'publish',
    startedAt: 611.4,
  );
  final e5f6 = Journal(
    'e5f6-run',
    parent: 'k7f2-run',
    node: 'notify',
    startedAt: 611.4,
  );

  final KnownOutcomes outcomes = outcomesOf({
    'is-empty-outcome': false,
    'verdict-outcome-1': 'returned',
    'verdict-outcome-2': 'accepted',
  });

  SessionData get session => sessionOf([k7f2, c3d4, e5f6]);
}
