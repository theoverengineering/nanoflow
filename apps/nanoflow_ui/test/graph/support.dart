// The graph screen of a graph file in test/layout/graphs/, for the screen's
// tests.

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

/// The graph file the screen opens: ~/Projects/release/nanoflow.graph.json.
final releaseFile =
    '${Platform.environment['HOME']}/Projects/release/$graphFileName';

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
      openModel: (_) => shown,
      now: now ?? () => at(100000),
    ),
    size: size,
  );
  await settle(tester);
  return shown;
}

/// Sessions of release as docs/design/graph.png has them, at [columnNow]:
/// a1b2 running, f0a5 running with a failed step, 7c3e failed, 4b8d
/// finished yesterday.
GraphModel columnModel() => ownedModel(
  file: releaseFile,
  changes: changesOf([
    Journal('a1b2-session', workflow: 'release')
      ..step('plan', 1, end: 5)
      ..step('build', 5),
    Journal('f0a5-session', workflow: 'release', startedAt: -2131)
      ..step('plan', -2130, end: -2120)
      ..step('build', -2120, end: -2100, failed: true)
      ..step('build', -2000),
    Journal('7c3e-session', workflow: 'release', startedAt: -4989)
      ..step('plan', -4988, end: -4700, failed: true)
      ..fail(-4989 + 378, 'StateError: plan failed'),
    Journal('4b8d-session', workflow: 'release', startedAt: -67816)
      ..step('plan', -67815, end: -67700)
      ..finish(-67816 + 184),
  ]),
);

/// 12m 26s after a1b2 started.
final columnNow = at(746);
