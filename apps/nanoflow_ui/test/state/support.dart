// Sessions written as journals, the way the engine writes them, for the
// tests of what the app derives from them.

import 'dart:async';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/outcomes.dart';
import 'package:nanoflow_ui/state/session_feed.dart';
import 'package:nanoflow_ui/state/step_files.dart';

/// The README's review graph, as a session holds it.
const reviewGraph = <String, Object?>{
  'start': 'collect',
  'types': {
    'Request': {
      'type': 'object',
      'required': ['branch'],
      'properties': {
        'branch': {'type': 'string'},
      },
    },
    'Change': {
      'type': 'object',
      'required': ['id', 'path'],
      'properties': {
        'id': {'type': 'string'},
        'path': {'type': 'string'},
      },
    },
    'Report': {
      'type': 'object',
      'required': ['change', 'findings'],
      'properties': {
        'change': {r'$ref': '#/Change'},
        'findings': {
          'type': 'array',
          'items': {'type': 'string'},
        },
      },
    },
  },
  'nodes': {
    'collect': {
      'command': 'nodes/collect/run.sh',
      'in': {r'$ref': '#/Request'},
      'out': {r'$ref': '#/Change'},
      'then': 'is-empty',
    },
    'is-empty': {
      'decide': 'nodes/is-empty/run.sh',
      'in': {r'$ref': '#/Change'},
      'then': 'discard',
      'else': 'inspect',
    },
    'inspect': {
      'command': 'nodes/inspect/run.sh',
      'in': {r'$ref': '#/Change'},
      'out': {r'$ref': '#/Report'},
      'then': 'verdict',
    },
    'verdict': {
      'decide': 'nodes/verdict/run.sh',
      'in': {r'$ref': '#/Report'},
      'then': {
        'accepted': ['publish', 'notify'],
        'returned': 'fix',
      },
    },
    'fix': {
      'command': 'nodes/fix/run.sh',
      'in': {r'$ref': '#/Report'},
      'out': {r'$ref': '#/Change'},
      'then': 'inspect',
    },
    'publish': {
      'command': 'nodes/publish/run.sh',
      'in': {r'$ref': '#/Report'},
    },
    'discard': {
      'command': 'nodes/discard/run.sh',
      'in': {r'$ref': '#/Change'},
    },
    'notify': {
      'command': 'nodes/notify/run.sh',
      'in': {r'$ref': '#/Report'},
    },
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

  /// A step of [node] given [input], started at [start], again at each of
  /// [restarts], and finished at [end] with [exit] and [output]; running
  /// without [end]. Returns its id.
  String step(
    String node,
    num start, {
    num? end,
    int exit = 0,
    String? input,
    String? output,
    List<num> restarts = const [],
  }) {
    final stepId = '${id.substring(0, 4)}-$node-${steps.length}';
    steps.add(
      Step(
        id: stepId,
        runId: id,
        inputId: input,
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

/// The changes a reader gives for the session [sessionId] holding [graph]
/// and its runs [journals].
List<Change> changesOf(
  List<Journal> journals, {
  String sessionId = 'a1b2-session',
  Map<String, Object?> graph = reviewGraph,
}) => [
  SessionAdded(Session(id: sessionId, graph: graph)),
  for (final journal in journals) ...[
    RunAdded(
      Run(id: journal.id, sessionId: sessionId, parentId: journal.parent),
    ),
    for (final step in journal.steps) StepAdded(step),
    for (final event in journal.events) EventAdded(event),
  ],
];

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
    k7f2
      ..step('collect', 0, end: 149, input: 'request', output: 'change-1')
      ..step(
        'is-empty',
        149,
        end: 150,
        input: 'change-1',
        output: 'is-empty-outcome',
      )
      ..step('inspect', 150, end: 342, input: 'change-1', output: 'report-1')
      ..step(
        'verdict',
        342,
        end: 342.4,
        input: 'report-1',
        output: 'verdict-outcome-1',
      )
      ..step('fix', 343, end: 369, input: 'report-1', output: 'change-2')
      ..step(
        'inspect',
        369,
        restarts: [400],
        end: 611,
        input: 'change-2',
        output: 'report-2',
      )
      ..step(
        'verdict',
        611,
        end: 611.3,
        input: 'report-2',
        output: 'verdict-outcome-2',
      )
      ..split(611.4);
    c3d4
      ..step('publish', 612, end: 640, input: 'report-2')
      ..finish(640);
    e5f6.step('notify', 612, input: 'report-2');
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

/// Step logs, documents and their files as a test sets them.
final class FakeFiles implements StepFiles {
  /// [logs] and [documents] by step and document id; [logErrors] are what
  /// following a step's log fails with.
  FakeFiles({
    Map<String, String> logs = const {},
    Map<String, Object?> documents = const {},
    Map<String, String> stepPaths = const {},
    Map<String, String> logPaths = const {},
    Map<String, String> documentPaths = const {},
    Map<String, Object> logErrors = const {},
  }) : logs = {...logs},
       documents = {...documents},
       stepPaths = {...stepPaths},
       logPaths = {...logPaths},
       documentPaths = {...documentPaths},
       logErrors = {...logErrors};

  /// What each step's command has written to its log so far.
  final Map<String, String> logs;
  final Map<String, Object?> documents;
  final Map<String, String> stepPaths;
  final Map<String, String> logPaths;
  final Map<String, String> documentPaths;
  final Map<String, Object> logErrors;
  final Map<String, Set<StreamController<String>>> _followers = {};

  /// How many times each document was read.
  final Map<String, int> reads = {};

  /// The steps whose logs are being followed now.
  Iterable<String> get followed =>
      _followers.entries.where((e) => e.value.isNotEmpty).map((e) => e.key);

  /// The step [stepId]'s command writes [text] to its log.
  void append(String stepId, String text) {
    logs[stepId] = '${logs[stepId] ?? ''}$text';
    for (final follower in [...?_followers[stepId]]) {
      follower.add(text);
    }
  }

  /// Reading the step [stepId]'s log fails once with [error]; reading goes
  /// on.
  void fail(String stepId, Object error) {
    for (final follower in [...?_followers[stepId]]) {
      follower.addError(error);
    }
  }

  @override
  Stream<String> stepLog(String sessionId, String runId, String stepId) {
    late final StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () {
        if (logErrors[stepId] case final error?) {
          controller.addError(error);
          return;
        }
        final text = logs[stepId] ?? '';
        if (text.isNotEmpty) controller.add(text);
        (_followers[stepId] ??= {}).add(controller);
      },
      onCancel: () => _followers[stepId]?.remove(controller),
    );
    return controller.stream;
  }

  @override
  Future<Object?> documentValue(String sessionId, String documentId) async {
    reads[documentId] = (reads[documentId] ?? 0) + 1;
    if (!documents.containsKey(documentId)) {
      throw PathNotFoundException(
        '$documentId.json',
        const OSError('No such file or directory', 2),
      );
    }
    return documents[documentId];
  }

  @override
  String? stepPath(String stepId) => stepPaths[stepId];

  @override
  String? logPath(String stepId) => logPaths[stepId];

  @override
  String? documentPath(String sessionId, String documentId) =>
      documentPaths[documentId];
}
