// The graph screen fed the sessions of docs/design/graph.png, for the
// screen's tests.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart' hide Route;
import 'package:nanoflow_ui/graph/graph_screen.dart';
import 'package:nanoflow_ui/platform/shell.dart';
import 'package:nanoflow_ui/state/graph_model.dart';

import '../state/support.dart';
import '../support/golden.dart';
import 'canvas/support.dart';

/// The graph file the screen opens: ~/Projects/review/review.yaml.
final reviewFile =
    '${Platform.environment['HOME']}/Projects/review/review.yaml';

/// The sessions column of docs/design/graph.png below a1b2, newest first:
/// f0a5 running with a failed run, 7c3e failed, 4b8d, 9e21 and c7aa
/// finished.
List<Change> olderSessions() => [
  ...splitSession(
    'f0a5',
    DateTime(2026, 9, 21, 13, 27, 40),
    took: 400,
    publish: End.failed,
    notify: End.running,
  ),
  ...splitSession(
    '7c3e',
    DateTime(2026, 9, 21, 12, 40, 2),
    took: 378,
    publish: End.failed,
  ),
  ...discardSession('4b8d', DateTime(2026, 9, 20, 19, 12, 55), took: 184),
  ...splitSession('9e21', DateTime(2026, 9, 20, 11, 40, 17), took: 1300),
  ...discardSession('c7aa', DateTime(2026, 9, 18, 16, 5, 33), took: 112),
];

/// How a run of a test session ends.
enum End { finished, failed, running }

/// Seconds from [t0] to the local time [local].
num _secondsTo(DateTime local) =>
    local.toUtc().difference(t0).inMilliseconds / 1000;

/// The id of the run of the session [id] that [letter] tells apart from
/// its other runs: `r7c3-run`.
String runOf(String id, String letter) => '$letter${id.substring(0, 3)}-run';

/// The session `<id>-s`, started at [start] (local time), whose one run
/// went to `discard` and finished [took] seconds later.
List<Change> discardSession(String id, DateTime start, {required num took}) {
  final s = _secondsTo(start);
  final run =
      Journal(runOf(id, 'r'), node: 'collect', startedAt: s, sessionId: '$id-s')
        ..step('collect', s, end: s + took / 2, output: '$id-change')
        ..step('is-empty', s + took / 2, end: s + took / 2 + 1)
        ..step('discard', s + took / 2 + 1, end: s + took)
        ..finish(s + took);
  return changesOf([run], sessionId: '$id-s');
}

/// The session `<id>-s`, started at [start] (local time), whose root run
/// split at `verdict` into one on `publish` and one on `notify`, which end
/// as [publish] and [notify] say, the last [took] seconds after [start].
List<Change> splitSession(
  String id,
  DateTime start, {
  required num took,
  End publish = End.finished,
  End notify = End.finished,
}) {
  final s = _secondsTo(start);
  final half = s + took / 2;
  final root =
      Journal(runOf(id, 'r'), node: 'collect', startedAt: s, sessionId: '$id-s')
        ..step('collect', s, end: s + 10, output: '$id-change')
        ..step('is-empty', s + 10, end: s + 11)
        ..step('inspect', s + 11, end: half - 1, output: '$id-report')
        ..step('verdict', half - 1, end: half)
        ..split(half);
  Journal child(String node, End end, num endsAt) {
    final run = Journal(
      runOf(id, node[0]),
      parent: root.id,
      node: node,
      startedAt: half,
      sessionId: '$id-s',
    );
    switch (end) {
      case End.finished:
        run
          ..step(node, half, end: endsAt)
          ..finish(endsAt);
      case End.failed:
        run.fail(
          run.step(node, half, end: endsAt, exit: 1),
          endsAt,
          'exited with code 1',
        );
      case End.running:
        run.step(node, half);
    }
    return run;
  }

  return changesOf([
    root,
    child('publish', publish, s + took),
    child('notify', notify, s + took - 5),
  ], sessionId: '$id-s');
}

/// The model of docs/design/graph.png with the sessions below a1b2 too, and
/// the review graph as the current graph; for the screen to own.
GraphModel mockupModel() {
  final mockup = Mockup();
  return ownedModel(
    current: Graph.fromJson(reviewGraph),
    changes: [
      ...changesOf([mockup.k7f2, mockup.c3d4, mockup.e5f6]),
      ...olderSessions(),
    ],
    outcomes: reviewOutcomes,
  );
}

/// The source of [model], as the tests set it.
FixedSource sourceOf(GraphModel model) => model.source as FixedSource;

/// Pumps a graph screen of [reviewFile] that owns [model] (by default
/// [mockupModel]) at [now] (by default [Mockup.now]), and lets the feed
/// reach it. Returns the model.
Future<GraphModel> pumpGraphScreen(
  WidgetTester tester, {
  GraphModel? model,
  Shell? shell,
  VoidCallback? onBack,
  DateTime Function()? now,
  Size size = mockupWindow,
}) async {
  final shown = model ?? mockupModel();
  await pumpScreen(
    tester,
    GraphScreen(
      path: reviewFile,
      shell: shell ?? Shell(environment: const {}),
      onBack: onBack ?? () {},
      openModel: (_, _) => shown,
      now: now ?? () => Mockup.now,
    ),
    size: size,
  );
  await settle(tester);
  return shown;
}
