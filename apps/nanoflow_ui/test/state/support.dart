// Sessions written as journals, the way the workflow library writes them,
// and graph files as describe writes them, for the tests of what the app
// derives from them.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/effect_files.dart';
import 'package:nanoflow_ui/state/effect_places.dart';
import 'package:nanoflow_ui/state/freshness.dart';
import 'package:nanoflow_ui/state/graph_file_source.dart';
import 'package:nanoflow_ui/state/log_rows.dart';
import 'package:nanoflow_ui/state/outcomes.dart';
import 'package:nanoflow_ui/state/session_feed.dart';
import 'package:path/path.dart' as p;

/// The fingerprint of the code [reviewGraphFile] was read from.
const reviewCode = 'sha256:review-code';

/// A graph file of the package `review_example` with two workflows,
/// `review` and `release`, as describe writes it; [fingerprint], [builds]
/// and [warnings] as given.
Map<String, Object?> graphFileJson({
  String fingerprint = reviewCode,
  Map<String, String> builds = const {},
  List<Map<String, Object?>> warnings = const [],
  String reviewEffect = 'collect',
}) => {
  'format': 2,
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
            'kind': 'effect',
            'name': reviewEffect,
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
            'kind': 'effect',
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
  String reviewEffect = 'collect',
}) => GraphFile.fromJson(
  graphFileJson(
    fingerprint: fingerprint,
    builds: builds,
    warnings: warnings,
    reviewEffect: reviewEffect,
  ),
);

/// What [Journal.effect] takes for "after the effect before it".
const _previous = '\u0000previous';

/// An effect node of a test graph.
Map<String, Object?> effectNode(String id, String name, int line) => {
  'id': id,
  'kind': 'effect',
  'name': name,
  'place': 'lib/packages.dart:$line',
};

/// A call node of a test graph, of the function [function].
Map<String, Object?> callNode(String id, String function, int line) => {
  'id': id,
  'kind': 'call',
  'functions': [function],
  'place': 'lib/packages.dart:$line',
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

/// The graph file of `lib/packages.dart` of the package `packages`, whose
/// workflows call functions that hold their effects (the line of each node
/// in the comments):
///
/// ```text
/// inPlace (3):  plan (4) → ship() (5) → announce (12)
/// ship (6):     upload (7) → verify (8) → tag (9)
/// viaCall (14): publish() (16) → announce (17)
/// publish (19): upload (20) → verify (21) → tag (22)
/// nested (24):  prepare() (25) → announce (37)
/// prepare (26): fetch (27) → compile() (28) → upload (34)
/// compile (29): build (30) → test (31)
/// ```
Map<String, Object?> packagesGraphJson() => {
  'format': 2,
  'package': 'packages',
  'fingerprint': 'sha256:packages-code',
  'sources': {'lib/packages.dart': 'sha256:c0c0'},
  'builds': <String, String>{},
  'workflows': [
    'lib/packages.dart#inPlace',
    'lib/packages.dart#nested',
    'lib/packages.dart#viaCall',
  ],
  'functions': {
    'lib/packages.dart#compile': {
      'name': 'compile',
      'place': 'lib/packages.dart:29',
      'body': chainBody([
        effectNode('1', 'build', 30),
        effectNode('2', 'test', 31),
      ]),
    },
    'lib/packages.dart#inPlace': {
      'name': 'inPlace',
      'place': 'lib/packages.dart:3',
      'body': chainBody([
        effectNode('1', 'plan', 4),
        callNode('2', 'lib/packages.dart#ship', 5),
        effectNode('3', 'announce', 12),
      ]),
    },
    'lib/packages.dart#nested': {
      'name': 'nested',
      'place': 'lib/packages.dart:24',
      'body': chainBody([
        callNode('1', 'lib/packages.dart#prepare', 25),
        effectNode('2', 'announce', 37),
      ]),
    },
    'lib/packages.dart#prepare': {
      'name': 'prepare',
      'place': 'lib/packages.dart:26',
      'body': chainBody([
        effectNode('1', 'fetch', 27),
        callNode('2', 'lib/packages.dart#compile', 28),
        effectNode('3', 'upload', 34),
      ]),
    },
    'lib/packages.dart#publish': {
      'name': 'publish',
      'place': 'lib/packages.dart:19',
      'body': chainBody([
        effectNode('1', 'upload', 20),
        effectNode('2', 'verify', 21),
        effectNode('3', 'tag', 22),
      ]),
    },
    'lib/packages.dart#ship': {
      'name': 'ship',
      'place': 'lib/packages.dart:6',
      'body': chainBody([
        effectNode('1', 'upload', 7),
        effectNode('2', 'verify', 8),
        effectNode('3', 'tag', 9),
      ]),
    },
    'lib/packages.dart#viaCall': {
      'name': 'viaCall',
      'place': 'lib/packages.dart:14',
      'body': chainBody([
        callNode('1', 'lib/packages.dart#publish', 16),
        effectNode('2', 'announce', 17),
      ]),
    },
  },
  'warnings': <Object?>[],
};

/// [packagesGraphJson] read.
GraphFile packagesGraphFile() => GraphFile.fromJson(packagesGraphJson());

/// Writes the graph [name] of [graph], by default [reviewGraphFile] — `review`
/// or `release` —, to its own file under `lib/` of the package in [dir], with
/// the package's `pubspec.yaml`, as describe does; gives the file's path.
String putGraphOf(String dir, String name, {GraphFile? graph}) {
  graph ??= reviewGraphFile();
  final function = graph.functions.values.firstWhere((f) => f.name == name);
  File(p.join(dir, 'pubspec.yaml')).writeAsStringSync('name: review_example\n');
  final file = File(p.join(dir, 'lib', '$name$graphFileSuffix'))
    ..parent.createSync(recursive: true);
  final own = OneGraphFile(
    package: graph.package,
    name: function.name,
    place: function.place,
    doc: function.doc,
    body: function.body,
    warnings: const [],
    fingerprint: graph.fingerprint,
    sources: graph.sources,
    builds: graph.builds,
  );
  file.writeAsStringSync(jsonEncode(own.toJson()));
  return file.path;
}

/// What a recording tool wrote into a fixture directory: the graph file, and
/// the sessions as the real library wrote them, by workflow, with the values
/// of their documents.
typedef Recorded = ({
  GraphFile graph,
  Map<String, SessionData> sessions,
  Map<String, Object?> documents,
});

/// Sessions the real library wrote for workflows written as functions — plan,
/// a call of publish (upload, verify) or a closure called in place with the
/// same, then announce on the stable channel — with the graph file describe
/// wrote for them: test/state/fixtures/calls. They stay as journal data;
/// nothing records them again.
Recorded recordedCalls() => _recorded('test/state/fixtures/calls');

/// The session the real library wrote for the `review` workflow of
/// examples/review, then a function, run on the branch its README uses,
/// `parseConfig` — collect, inspect, fix, inspect, then publish and notify
/// side by side — with the example's graph file: test/state/fixtures/review.
/// It stays as journal data; nothing records it again.
Recorded recordedReview() => _recorded('test/state/fixtures/review');

Recorded _recorded(String dir) {
  Object? read(String name) =>
      jsonDecode(File('$dir/$name').readAsStringSync());
  final sessions = <String, SessionData>{};
  final documents = <String, Object?>{};
  for (final raw in read('sessions.json')! as List<Object?>) {
    final json = raw! as Map<String, Object?>;
    final session = Session.fromJson(json['session']! as Map<String, Object?>);
    sessions[session.workflow] = SessionData(
      session,
      effects: [
        for (final effect in json['effects']! as List<Object?>)
          Effect.fromJson(effect! as Map<String, Object?>),
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

/// The place of line [line] of `lib/packages.dart`.
String packagesAt(int line) => 'lib/packages.dart:$line';

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
  final List<Effect> effects = [];

  Session get session =>
      Session(id: id, workflow: workflow, graph: graph, inputId: null);

  /// An effect [name] at [place] started at [start], again at each of
  /// [restarts], and finished at [end] with [output], or failed then when
  /// [failed]; running without [end]. Its [key] is `<name>#<n>@0…0` by
  /// default, `n` counting the effects of that name; it comes [after] the
  /// effect of that key, by default the effect before it. Returns its id.
  ///
  /// The default is how the library keys an effect awaited where the one
  /// before it was, not one after an awaited call, a closure called in place
  /// or a wait: the library keys that one after the effect before them
  /// (spec §4.3), and a test of such code says so.
  String effect(
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
    final effectId = '${id.substring(0, 4)}-$name-${effects.length}';
    final n = effects.where((effect) => effect.name == name).length + 1;
    effects.add(
      Effect(
        id: effectId,
        sessionId: id,
        name: name,
        key: key ?? '$name#$n@0000000000000000',
        after: identical(after, _previous) ? effects.lastOrNull?.key : after,
        place: place,
        outputId: failed ? null : output,
        log: logFileName,
      ),
    );
    for (final time in [start, ...restarts]) {
      events.add(EffectStarted(time: at(time), effectId: effectId));
    }
    if (end != null) {
      events.add(
        failed
            ? EffectFailed(
                time: at(end),
                effectId: effectId,
                error: 'StateError: $name failed',
                stack: '#0 main',
              )
            : EffectFinished(
                time: at(end),
                effectId: effectId,
                outputId: output,
              ),
      );
    }
    return effectId;
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
    effects: effects,
    owner: ownerChanged?.owner,
    alive: ownerChanged?.alive,
  );

  /// The changes a reader gives for this session: what it tells of the
  /// owner after the events.
  List<Change> get changes => [
    SessionAdded(session),
    for (final effect in effects) EffectAdded(effect),
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

/// Effect logs, documents and their files as a test sets them.
final class FakeFiles implements EffectFiles {
  /// [logs] and [documents] by effect and document id; [logErrors] are what
  /// following an effect's log fails with.
  FakeFiles({
    Map<String, String> logs = const {},
    Map<String, Object?> documents = const {},
    Map<String, String> effectPaths = const {},
    Map<String, String> logPaths = const {},
    Map<String, String> documentPaths = const {},
    Map<String, Object> logErrors = const {},
  }) : logs = {...logs},
       documents = {...documents},
       effectPaths = {...effectPaths},
       logPaths = {...logPaths},
       documentPaths = {...documentPaths},
       logErrors = {...logErrors};

  /// What each effect has written to its log so far.
  final Map<String, String> logs;
  final Map<String, Object?> documents;
  final Map<String, String> effectPaths;
  final Map<String, String> logPaths;
  final Map<String, String> documentPaths;
  final Map<String, Object> logErrors;
  final Map<String, Set<StreamController<String>>> _followers = {};

  /// How many times each document was read.
  final Map<String, int> reads = {};

  /// The effects whose logs are being followed now.
  Iterable<String> get followed =>
      _followers.entries.where((e) => e.value.isNotEmpty).map((e) => e.key);

  /// The effect [effectId] writes [text] to its log.
  void append(String effectId, String text) {
    logs[effectId] = '${logs[effectId] ?? ''}$text';
    for (final follower in [...?_followers[effectId]]) {
      follower.add(text);
    }
  }

  /// Reading the effect [effectId]'s log fails once with [error]; reading goes
  /// on.
  void fail(String effectId, Object error) {
    for (final follower in [...?_followers[effectId]]) {
      follower.addError(error);
    }
  }

  @override
  Stream<String> effectLog(String sessionId, String effectId) {
    late final StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () {
        if (logErrors[effectId] case final error?) {
          controller.addError(error);
          return;
        }
        final text = logs[effectId] ?? '';
        if (text.isNotEmpty) controller.add(text);
        (_followers[effectId] ??= {}).add(controller);
      },
      onCancel: () => _followers[effectId]?.remove(controller),
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
  String? effectPath(String effectId) => effectPaths[effectId];

  @override
  String? logPath(String effectId) => logPaths[effectId];

  @override
  String? documentPath(String sessionId, String documentId) =>
      documentPaths[documentId];
}

/// A graph file, its error and whether it is missing, as the test sets
/// them; nothing is read.
final class FixedGraphFile extends GraphFileSource {
  FixedGraphFile([this._graph, String file = '/nowhere/lib/review.graph.json'])
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

/// A workflow `w`: plan, then publish of [packagesGraphFile] (upload,
/// verify) called once for each package, then announce.
const publishingWorkflow = GraphFunction(
  id: 'lib/w.dart#w',
  name: 'w',
  place: 'lib/w.dart:1',
  body: GraphBody(
    nodes: [
      EffectNode(id: '1', place: 'lib/w.dart:2', name: 'plan'),
      CallNode(
        id: '2',
        place: 'lib/w.dart:3',
        functions: ['lib/packages.dart#publish'],
      ),
      EffectNode(id: '3', place: 'lib/w.dart:4', name: 'announce'),
    ],
    edges: [],
  ),
);

/// Where the effects of [publishingSession] are on [publishingWorkflow].
EffectPlaces publishingPlaces() => EffectPlaces.of(publishingWorkflow, {
  ...packagesGraphFile().functions,
  publishingWorkflow.id: publishingWorkflow,
});

/// [publishingWorkflow] over core, tool and docs: core's publish done,
/// tool's verify failed, docs' verify running; announce done.
SessionData publishingSession() {
  final j = Journal('d5e6-session', workflow: 'w')
    ..effect('plan', 0, end: 10, place: 'lib/w.dart:2', key: 'p');
  for (final (i, pkg) in ['core', 'tool', 'docs'].indexed) {
    j
      ..effect(
        'upload',
        10 + i,
        end: 20 + i,
        place: packagesAt(20),
        key: 'u$pkg',
        after: 'p',
      )
      ..effect(
        'verify',
        30 + i,
        end: pkg == 'docs' ? null : 40 + i,
        failed: pkg == 'tool',
        place: packagesAt(21),
        key: 'v$pkg',
        after: 'u$pkg',
      );
  }
  j.effect('announce', 50, end: 60, place: 'lib/w.dart:4', after: 'p');
  return j.data;
}

/// The `Logs` rows of [publishingSession] at 100 s, the runs of [open] open.
List<LogRow> publishingRows({Set<String> open = const {}}) {
  final session = publishingSession();
  return logRows(
    session,
    effects: session.state.effects,
    places: publishingPlaces(),
    now: at(100),
    calls: callsIn(publishingWorkflow.body),
    open: open,
  );
}
