// The graph screen of a graph file in test/layout/graphs/, for the screen's
// tests.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/graph/graph_screen.dart';
import 'package:nanoflow_ui/platform/shell.dart';
import 'package:nanoflow_ui/state/graph_model.dart';
import 'package:path/path.dart' as p;

import '../state/support.dart';
import '../support/golden.dart';
import 'canvas/support.dart';

/// The graph file the screen opens: ~/Projects/release/nanoflow.graph.json.
final releaseFile =
    '${Platform.environment['HOME']}/Projects/release/$graphFileName';

/// A shell that notes the files it is asked to open at a line, and opens
/// them but when told not to.
class PlaceShell extends Shell {
  PlaceShell({this.opens = true});

  final bool opens;

  /// What it was asked to open: the file and the line.
  final opened = <(String, int)>[];

  @override
  Future<bool> openAtLine(String path, int line) async {
    opened.add((path, line));
    return opens;
  }
}

/// Pumps a graph screen of [path] (by default [releaseFile]) that owns
/// [model] (by default the release fixture's) at [now] (by default when
/// the model is opened), and lets the feed reach it. Returns the model.
Future<GraphModel> pumpGraphScreen(
  WidgetTester tester, {
  String? path,
  GraphModel? model,
  Shell? shell,
  VoidCallback? onBack,
  DateTime Function()? now,
  Size size = mockupWindow,
}) async {
  final shown = model ?? ownedModel(file: path ?? releaseFile);
  await pumpScreen(
    tester,
    GraphScreen(
      path: path ?? releaseFile,
      shell: shell ?? Shell(),
      onBack: onBack ?? () {},
      openModel: (_, {store, session}) => shown,
      now: now ?? () => at(100000),
    ),
    size: size,
  );
  await settle(tester);
  return shown;
}

/// Sessions of release as docs/design/graph.png has them, at [columnNow]:
/// a1b2 running, f0a5 running with a failed effect, 7c3e failed, 4b8d
/// finished yesterday.
GraphModel columnModel() => ownedModel(
  file: releaseFile,
  changes: changesOf([
    Journal('a1b2-session', workflow: 'release')
      ..effect('plan', 1, end: 5)
      ..effect('build', 5),
    Journal('f0a5-session', workflow: 'release', startedAt: -2131)
      ..effect('plan', -2130, end: -2120)
      ..effect('build', -2120, end: -2100, failed: true)
      ..effect('build', -2000),
    Journal('7c3e-session', workflow: 'release', startedAt: -4989)
      ..effect('plan', -4988, end: -4700, failed: true)
      ..fail(-4989 + 378, 'StateError: plan failed'),
    Journal('4b8d-session', workflow: 'release', startedAt: -67816)
      ..effect('plan', -67815, end: -67700)
      ..finish(-67816 + 184),
  ]),
);

/// 12m 26s after a1b2 started.
final columnNow = at(746);

/// The graph file of the review example the screen opens:
/// ~/Projects/review/nanoflow.graph.json.
final reviewFile =
    '${Platform.environment['HOME']}/Projects/review/$graphFileName';

/// Session a1b2 of the review example as docs/design/graph.png has it, on
/// the example's code: collect, inspect, fix, inspect again — started twice
/// — then publish done and notify running since 14:13:23, both after the
/// second inspect, as the library keys effects called side by side; at
/// [columnNow] it has run for 12m 26s. Once [finished], notify is done at
/// 14:14:51 and the session a second later. Its snapshot is [graph], by
/// default the review example's graph file.
Journal reviewSession({bool finished = false, GraphFile? graph}) {
  graph ??= graphFileNamed('review');
  String place(int line) => 'lib/review.dart:$line';
  final j =
      Journal('a1b2-session', graph: graph.toJson(), code: graph.fingerprint)
        ..effect('collect', 0, end: 149, output: 'change-1', place: place(49))
        ..effect('inspect', 150, end: 342, output: 'report-1', place: place(55))
        ..effect('fix', 343, end: 369, output: 'change-2', place: place(63))
        ..effect(
          'inspect',
          369,
          end: 611,
          output: 'report-2',
          place: place(55),
          restarts: [520],
        );
  final inspected = j.effects.last.key;
  j
    ..effect(
      'publish',
      612,
      end: 613,
      output: 'published',
      place: place(58),
      after: inspected,
    )
    ..effect(
      'notify',
      612,
      end: finished ? 700 : null,
      place: place(59),
      after: inspected,
    );
  if (finished) j.finish(701);
  return j;
}

/// The ids of the effects of [reviewSession], in order.
const reviewEffects = [
  'a1b2-collect-0',
  'a1b2-inspect-1',
  'a1b2-fix-2',
  'a1b2-inspect-3',
  'a1b2-publish-4',
  'a1b2-notify-5',
];

/// The log of the effect on `notify` in docs/design/graph.png.
const notifyLog = '''
loading report for change c4f1a9
2 findings, 3 subscribers
sending to subscriber 1 of 3 … ok
sending to subscriber 2 of 3 … ok
subscriber 3: 429 too many requests, retrying in 60s
subscriber 3: 429 too many requests, retrying in 120s
''';

/// The directory of [reviewSession], under [reviewFile]'s `runs`.
final reviewSessionDir = p.join(
  runsDirOf(p.dirname(reviewFile)),
  sessionDirName('review', t0, 'a1b2-session'),
);

/// The directory of the effect [effectId] of [reviewSession] named [name],
/// started at [startedAt] seconds.
String reviewEffectDir(String name, String effectId, num startedAt) => p.join(
  reviewSessionDir,
  effectsDirName,
  effectDirName(at(startedAt), name, effectId),
);

/// The file of the effect on `notify`'s log.
final notifyLogPath = p.join(
  reviewEffectDir('notify', 'a1b2-notify-5', 612),
  logFileName,
);

/// The directory of the second effect on `inspect`.
final inspectEffectPath = reviewEffectDir('inspect', 'a1b2-inspect-3', 369);

/// The file of the document [id] of [reviewSession].
String reviewDocumentPath(String id) =>
    p.join(reviewSessionDir, documentsDirName, documentFileName(id));

/// What the documents of [reviewSession] hold.
const reviewDocuments = <String, Object?>{
  'change-1': {'id': 'c4f1a9', 'path': 'lib/parseConfig.dart'},
  'report-1': {
    'change': {'id': 'c4f1a9', 'path': 'lib/parseConfig.dart'},
    'findings': ['lib/parseConfig.dart: file names are lower_snake_case'],
  },
  'change-2': {'id': 'c4f1a9', 'path': 'lib/parse_config.dart'},
  'report-2': {
    'change': {'id': 'c4f1a9', 'path': 'lib/parse_config.dart'},
    'findings': <String>[],
  },
  'published': null,
};

/// The logs and documents of [reviewSession] and their files: the effect on
/// `notify` has written [notifyLog] so far.
FakeFiles reviewFiles() => FakeFiles(
  logs: const {'a1b2-notify-5': notifyLog},
  documents: reviewDocuments,
  effectPaths: {'a1b2-inspect-3': inspectEffectPath},
  logPaths: {'a1b2-notify-5': notifyLogPath},
  documentPaths: {
    for (final id in reviewDocuments.keys) id: reviewDocumentPath(id),
  },
);

/// The graph file of the describe fixture `inline` the screen opens:
/// ~/Projects/inline/nanoflow.graph.json.
final inlineFile =
    '${Platform.environment['HOME']}/Projects/inline/$graphFileName';

/// A session of `inPlace` of the describe fixture `inline` over core, tool
/// and cli, as the library writes it: core done, tool on verify, cli on
/// tag; at [columnNow].
Journal copiesSession() {
  final graph = graphFileNamed('inline');
  String place(int line) => 'lib/inline.dart:$line';
  final j = Journal(
    'c0c0-session',
    workflow: 'inPlace',
    graph: graph.toJson(),
    code: graph.fingerprint,
  );
  for (final (i, pkg) in ['core', 'tool', 'cli'].indexed) {
    j.effect(
      'upload',
      10 + i,
      end: 60 + i * 30,
      output: '$pkg:uploaded',
      place: place(10),
      key: 'upload#${i + 1}@e3b0',
      after: null,
    );
  }
  for (final (i, pkg) in ['core', 'tool', 'cli'].indexed) {
    j.effect(
      'verify',
      61 + i * 30,
      end: pkg == 'tool' ? null : 120 + i * 30,
      output: '$pkg:verified',
      place: place(11),
      key: 'verify#1@$pkg',
      after: 'upload#${i + 1}@e3b0',
    );
  }
  for (final pkg in ['core', 'cli']) {
    j.effect(
      'tag',
      pkg == 'core' ? 121 : 181,
      end: pkg == 'core' ? 150 : null,
      output: '$pkg:tagged',
      place: place(12),
      key: 'tag#1@$pkg',
      after: 'verify#1@$pkg',
    );
  }
  return j;
}

/// The model of the fixture `inline` at [inlineFile] with
/// [copiesSession], its outputs as the effects gave them. For the screen to
/// own.
GraphModel copiesModel() => ownedModel(
  graph: graphFileNamed('inline'),
  file: inlineFile,
  changes: copiesSession().changes,
  documents: {
    for (final pkg in ['core', 'tool', 'cli'])
      for (final what in ['uploaded', 'verified', 'tagged'])
        '$pkg:$what': '$pkg:$what',
  },
);

/// Pumps the graph screen of [reviewFile] owning [model], by default
/// [reviewModel], at [now], by default [columnNow]. Returns the model.
Future<GraphModel> pumpReview(
  WidgetTester tester, {
  GraphModel? model,
  Shell? shell,
  DateTime Function()? now,
  Size size = mockupWindow,
}) => pumpGraphScreen(
  tester,
  path: reviewFile,
  model: model ?? reviewModel(),
  shell: shell,
  now: now ?? () => columnNow,
  size: size,
);

/// The model of the review example's graph file at [reviewFile] with
/// [reviewSession], [finished] or not, fed [more] after it; the effects'
/// logs and documents are [files], by default [reviewFiles]. The graph file
/// and the session's snapshot are [graph], by default the example's. For
/// the screen to own.
GraphModel reviewModel({
  FakeFiles? files,
  List<Change> more = const [],
  bool finished = false,
  GraphFile? graph,
}) => ownedModel(
  graph: graph ?? graphFileNamed('review'),
  file: reviewFile,
  changes: [
    ...reviewSession(finished: finished, graph: graph).changes,
    ...more,
  ],
  documents: reviewDocuments,
  files: files ?? reviewFiles(),
);
