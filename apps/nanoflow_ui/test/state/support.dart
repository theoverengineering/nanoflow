// Sessions written as journals, the way the workflow library writes them,
// and graph files as describe writes them, for the tests of what the app
// derives from them.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/freshness.dart';
import 'package:nanoflow_ui/state/graph_file_source.dart';
import 'package:nanoflow_ui/state/outcomes.dart';
import 'package:nanoflow_ui/state/session_feed.dart';
import 'package:nanoflow_ui/state/step_files.dart';

/// The fingerprint of the code [reviewGraphFile] was read from.
const reviewCode = 'sha256:review-code';

/// A graph file of the package `review_example` with two workflows,
/// `review` and `release`, as describe writes it; [fingerprint], [builds]
/// and [warnings] as given.
Map<String, Object?> graphFileJson({
  String fingerprint = reviewCode,
  Map<String, String> builds = const {},
  List<Map<String, Object?>> warnings = const [],
  String reviewStep = 'collect',
}) => {
  'format': 1,
  'package': 'review_example',
  'fingerprint': fingerprint,
  'sources': {'bin/main.dart': 'sha256:aa11', 'lib/review.dart': 'sha256:9f2c'},
  'builds': builds,
  'workflows': ['lib/review.dart#review', 'lib/release.dart#release'],
  'functions': {
    'lib/review.dart#review': {
      'name': 'review',
      'place': 'lib/review.dart:21',
      'body': {
        'nodes': [
          {
            'id': '1',
            'kind': 'step',
            'name': reviewStep,
            'place': 'lib/review.dart:22',
          },
        ],
        'edges': [
          {'from': null, 'to': '1', 'label': null},
          {'from': '1', 'to': null, 'label': null},
        ],
      },
    },
    'lib/release.dart#release': {
      'name': 'release',
      'place': 'lib/release.dart:9',
      'body': {
        'nodes': [
          {
            'id': '1',
            'kind': 'step',
            'name': 'plan',
            'place': 'lib/release.dart:10',
          },
        ],
        'edges': [
          {'from': null, 'to': '1', 'label': null},
          {'from': '1', 'to': null, 'label': null},
        ],
      },
    },
  },
  'warnings': warnings,
};

/// [graphFileJson] read.
GraphFile reviewGraphFile({
  String fingerprint = reviewCode,
  Map<String, String> builds = const {},
  List<Map<String, Object?>> warnings = const [],
  String reviewStep = 'collect',
}) => GraphFile.fromJson(
  graphFileJson(
    fingerprint: fingerprint,
    builds: builds,
    warnings: warnings,
    reviewStep: reviewStep,
  ),
);

/// What [Journal.step] takes for "after the step before it".
const _previous = '\u0000previous';

/// A step node of a test graph.
Map<String, Object?> stepNode(String id, String name, int line) => {
  'id': id,
  'kind': 'step',
  'name': name,
  'place': 'lib/copies.dart:$line',
};

/// A body of a test graph whose [nodes] follow one another from its entry
/// to its exit.
Map<String, Object?> chainBody(List<Map<String, Object?>> nodes) => {
  'nodes': nodes,
  'edges': [
    for (var i = 0; i <= nodes.length; i++)
      {
        'from': i == 0 ? null : nodes[i - 1]['id'],
        'to': i == nodes.length ? null : nodes[i]['id'],
        'label': null,
      },
  ],
};

/// The graph file describe writes for `lib/copies.dart` of the package
/// `copies`, whose workflows run copies side by side as the prototype
/// step_keys does (the line of each step in the comments):
///
/// ```dart
/// Future<String> inPlace(Flow f, List<String> packages) async {
///   final plan = await f.step('plan', …);                     // 4
///   final results = await Future.wait([                       // 5
///     for (final pkg in plan) () async {
///       final up = await f.step('upload', …);                 // 7
///       final ok = await f.step('verify', …);                 // 8
///       return f.step('tag', …);                              // 9
///     }(),
///   ]);
///   return f.step('announce', …);                             // 12
/// }
///
/// Future<String> viaCall(Flow f, List<String> packages) async {
///   final results = await Future.wait([                       // 15
///     for (final pkg in packages) publish(f, pkg),
///   ]);
///   return f.step('announce', …);                             // 17
/// }
///
/// Future<String> publish(Flow f, String pkg) async {
///   final up = await f.step('upload', …);                     // 20
///   final ok = await f.step('verify', …);                     // 21
///   return f.step('tag', …);                                  // 22
/// }
///
/// Future<String> nested(Flow f, List<String> packages) async {
///   final results = await Future.wait([                       // 25
///     for (final pkg in packages) () async {
///       final src = await f.step('fetch', …);                 // 27
///       final builds = await Future.wait([                    // 28
///         for (final target in targets) () async {
///           final bin = await f.step('build', …);             // 30
///           return f.step('test', …);                         // 31
///         }(),
///       ]);
///       return f.step('upload', …);                           // 34
///     }(),
///   ]);
///   return f.step('announce', …);                             // 37
/// }
/// ```
Map<String, Object?> copiesGraphJson() => {
  'format': 1,
  'package': 'copies',
  'fingerprint': 'sha256:copies-code',
  'sources': {'lib/copies.dart': 'sha256:c0c0'},
  'builds': <String, String>{},
  'workflows': [
    'lib/copies.dart#inPlace',
    'lib/copies.dart#nested',
    'lib/copies.dart#viaCall',
  ],
  'functions': {
    'lib/copies.dart#inPlace': {
      'name': 'inPlace',
      'place': 'lib/copies.dart:3',
      'body': chainBody([
        stepNode('1', 'plan', 4),
        {
          'id': '2',
          'kind': 'copies',
          'label': 'pkg in plan',
          'place': 'lib/copies.dart:5',
          'body': chainBody([
            stepNode('1', 'upload', 7),
            stepNode('2', 'verify', 8),
            stepNode('3', 'tag', 9),
          ]),
        },
        stepNode('3', 'announce', 12),
      ]),
    },
    'lib/copies.dart#nested': {
      'name': 'nested',
      'place': 'lib/copies.dart:24',
      'body': chainBody([
        {
          'id': '1',
          'kind': 'copies',
          'label': 'pkg in packages',
          'place': 'lib/copies.dart:25',
          'body': chainBody([
            stepNode('1', 'fetch', 27),
            {
              'id': '2',
              'kind': 'copies',
              'label': 'target in targets',
              'place': 'lib/copies.dart:28',
              'body': chainBody([
                stepNode('1', 'build', 30),
                stepNode('2', 'test', 31),
              ]),
            },
            stepNode('3', 'upload', 34),
          ]),
        },
        stepNode('2', 'announce', 37),
      ]),
    },
    'lib/copies.dart#publish': {
      'name': 'publish',
      'place': 'lib/copies.dart:19',
      'body': chainBody([
        stepNode('1', 'upload', 20),
        stepNode('2', 'verify', 21),
        stepNode('3', 'tag', 22),
      ]),
    },
    'lib/copies.dart#viaCall': {
      'name': 'viaCall',
      'place': 'lib/copies.dart:14',
      'body': chainBody([
        {
          'id': '1',
          'kind': 'copies',
          'label': 'pkg in packages',
          'place': 'lib/copies.dart:15',
          'body': chainBody([
            {
              'id': '1',
              'kind': 'call',
              'functions': ['lib/copies.dart#publish'],
              'place': 'lib/copies.dart:16',
            },
          ]),
        },
        stepNode('2', 'announce', 17),
      ]),
    },
  },
  'warnings': <Object?>[],
};

/// [copiesGraphJson] read.
GraphFile copiesGraphFile() => GraphFile.fromJson(copiesGraphJson());

/// Sessions the real library wrote for the workflows of
/// tests/e2e/test/fixtures/copies — in place, given to map, through a
/// call, copies in copies — with the graph file describe wrote for them
/// and the values of their documents: test/state/fixtures/copies.
///
/// Recorded again with
///
/// ```sh
/// cd tests/e2e
/// dart run tool/record_copies.dart ../../apps/nanoflow_ui/test/state/fixtures/copies
/// ```
///
/// whenever the library changes how it keys steps (decision D1).
({
  GraphFile graph,
  Map<String, SessionData> sessions,
  Map<String, Object?> documents,
})
recordedCopies() {
  const dir = 'test/state/fixtures/copies';
  Object? read(String name) =>
      jsonDecode(File('$dir/$name').readAsStringSync());
  final sessions = <String, SessionData>{};
  final documents = <String, Object?>{};
  for (final raw in read('sessions.json')! as List<Object?>) {
    final json = raw! as Map<String, Object?>;
    final session = Session.fromJson(json['session']! as Map<String, Object?>);
    sessions[session.workflow] = SessionData(
      session,
      steps: [
        for (final step in json['steps']! as List<Object?>)
          Step.fromJson(step! as Map<String, Object?>),
      ],
      events: [
        for (final event in json['events']! as List<Object?>)
          Event.fromJson(event! as Map<String, Object?>),
      ],
    );
    documents.addAll(json['documents']! as Map<String, Object?>);
  }
  return (
    graph: GraphFile.fromJson(read(graphFileName)! as Map<String, Object?>),
    sessions: sessions,
    documents: documents,
  );
}

/// The place of line [line] of `lib/copies.dart`.
String copiesAt(int line) => 'lib/copies.dart:$line';

/// 14:03:11 local time on 2026-09-21: when the mockups' session a1b2 starts.
final DateTime t0 = DateTime(2026, 9, 21, 14, 3, 11).toUtc();

/// [t0] moved on by [seconds], to the millisecond.
DateTime at(num seconds) =>
    t0.add(Duration(milliseconds: (seconds * 1000).round()));

/// A session and its journal, written event by event.
final class Journal {
  /// The session [id] of [workflow] holding [graph], created at [startedAt]
  /// (seconds after [t0]) by [code]; no `session-started` yet when
  /// [startedAt] is `null`.
  Journal(
    this.id, {
    this.workflow = 'review',
    Map<String, Object?>? graph,
    bool snapshot = true,
    num? startedAt = 0,
    String? code = reviewCode,
  }) : graph = snapshot ? graph ?? graphFileJson() : null {
    if (startedAt != null) {
      events.add(SessionStarted(time: at(startedAt), code: code));
    }
  }

  final String id;
  final String workflow;
  final Map<String, Object?>? graph;
  final List<Event> events = [];
  final List<Step> steps = [];

  Session get session =>
      Session(id: id, workflow: workflow, graph: graph, inputId: null);

  /// A step [name] at [place] started at [start], again at each of
  /// [restarts], and finished at [end] with [output], or failed then when
  /// [failed]; running without [end]. Its [key] is `<name>#<n>@0…0` by
  /// default, `n` counting the steps of that name; it comes [after] the
  /// step of that key, by default the step before it. Returns its id.
  String step(
    String name,
    num start, {
    num? end,
    bool failed = false,
    String? output,
    String? place,
    List<num> restarts = const [],
    String? key,
    String? after = _previous,
  }) {
    final stepId = '${id.substring(0, 4)}-$name-${steps.length}';
    final n = steps.where((step) => step.name == name).length + 1;
    steps.add(
      Step(
        id: stepId,
        sessionId: id,
        name: name,
        key: key ?? '$name#$n@0000000000000000',
        after: identical(after, _previous) ? steps.lastOrNull?.key : after,
        place: place,
        outputId: failed ? null : output,
        log: logFileName,
      ),
    );
    for (final time in [start, ...restarts]) {
      events.add(StepStarted(time: at(time), stepId: stepId));
    }
    if (end != null) {
      events.add(
        failed
            ? StepFailed(
                time: at(end),
                stepId: stepId,
                error: 'StateError: $name failed',
                stack: '#0 main',
              )
            : StepFinished(time: at(end), stepId: stepId, outputId: output),
      );
    }
    return stepId;
  }

  /// The session goes on at [time] by [code], with a new snapshot of the
  /// graph in the document [graphId].
  void resume(num time, {String? code = reviewCode, String? graphId}) =>
      events.add(SessionResumed(time: at(time), code: code, graphId: graphId));

  void finish(num time) =>
      events.add(SessionFinished(time: at(time), outputId: null));

  void fail(num time, String error) =>
      events.add(SessionFailed(time: at(time), error: error, stack: '#0 main'));

  /// What the reader last told of the session's owner; `null` while it has
  /// told nothing.
  OwnerChanged? ownerChanged;

  /// The reader tells that [owner] owns the session, and whether its
  /// process runs: [alive].
  void owned(Owner? owner, {required bool? alive}) =>
      ownerChanged = OwnerChanged(sessionId: id, owner: owner, alive: alive);

  /// The process that ran the session is gone: the reader tells `alive:
  /// false` of [testOwner].
  void processGone() => owned(testOwner, alive: false);

  SessionData get data => SessionData(
    session,
    events: events,
    steps: steps,
    owner: ownerChanged?.owner,
    alive: ownerChanged?.alive,
  );

  /// The changes a reader gives for this session: what it tells of the
  /// owner after the events.
  List<Change> get changes => [
    SessionAdded(session),
    for (final step in steps) StepAdded(step),
    for (final event in events) EventAdded(sessionId: id, event: event),
    ?ownerChanged,
  ];
}

/// The process that owns the sessions of the tests: started a second
/// before [t0].
final testOwner = Owner(pid: 4242, started: at(-1));

/// The changes a reader gives for [journals].
List<Change> changesOf(List<Journal> journals) => [
  for (final journal in journals) ...journal.changes,
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

  /// What each step has written to its log so far.
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

  /// The step [stepId] writes [text] to its log.
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
  Stream<String> stepLog(String sessionId, String stepId) {
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

/// A graph file, its error and whether it is missing, as the test sets
/// them; nothing is read.
final class FixedGraphFile extends GraphFileSource {
  FixedGraphFile([this._graph, String file = '/nowhere/$graphFileName'])
    : super(file: file);

  GraphFile? _graph;
  String? _error;
  bool _fileMissing = false;

  /// Whether the source has been disposed.
  bool disposed = false;

  @override
  Future<void> start() async {}

  @override
  GraphFile? get graph => _graph;

  /// The file has been read again: [graph] is in it now.
  set graph(GraphFile? graph) {
    _graph = graph;
    notifyListeners();
  }

  @override
  String? get error => _error;

  set error(String? error) {
    _error = error;
    notifyListeners();
  }

  @override
  bool get fileMissing => _fileMissing;

  set fileMissing(bool missing) {
    _fileMissing = missing;
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

/// The freshness of a graph file as the test sets it; nothing is checked.
final class FixedFreshness extends FreshnessWatch {
  FixedFreshness(super.source);

  Freshness? _freshness;

  @override
  void start() {}

  @override
  Freshness? get freshness => _freshness;

  set freshness(Freshness? freshness) {
    _freshness = freshness;
    notifyListeners();
  }
}
