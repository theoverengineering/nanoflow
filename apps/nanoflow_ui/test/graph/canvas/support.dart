// Graph screen models fed the sessions of the mockups, for the canvas tests.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart' hide Route;
import 'package:nanoflow_ui/platform/shell.dart';
import 'package:nanoflow_ui/state/graph_model.dart';
import 'package:nanoflow_ui/state/graph_source.dart';
import 'package:nanoflow_ui/state/outcomes.dart';
import 'package:nanoflow_ui/state/session_feed.dart';

import '../../state/support.dart';

/// The size of the canvas in docs/design/graph.html: the window less the
/// sessions column, the header and the `Logs` panel.
const reviewCanvas = Size(1440 - 272, 900 - 48 - 280);

/// The size of the canvas in docs/design/task-graph.html.
const taskCanvas = Size(2000 - 272, 1000 - 48 - 280);

/// A current graph that stays as it is given; no programs are started.
final class FixedSource extends GraphSource {
  FixedSource(this._graph)
    : super(
        file: '/nowhere/review.yaml',
        shell: Shell(environment: const {}),
      );

  final Graph? _graph;

  @override
  Graph? get graph => _graph;
}

/// A graph screen's model fed [changes], whose fork outputs hold [outcomes],
/// with [current] as the current graph. The graph is opened after everything
/// in the mockups, so their sessions are selected.
GraphModel modelOf({
  List<Change> changes = const [],
  Map<String, Object?> outcomes = const {},
  Graph? current,
}) {
  final model = GraphModel(
    source: FixedSource(current),
    feed: SessionFeed(Stream.fromIterable(changes)),
    outcomes: Outcomes((_, documentId) async => outcomes[documentId]),
    now: () => at(100000),
  );
  addTearDown(model.dispose);
  return model;
}

/// The model of docs/design/graph.png: session a1b2, run e5f6 and its step
/// on `notify` selected; [current] is the current graph.
GraphModel reviewModel({Graph? current}) {
  final mockup = Mockup();
  return modelOf(
    current: current,
    changes: changesOf([mockup.k7f2, mockup.c3d4, mockup.e5f6]),
    outcomes: const {
      'is-empty-outcome': false,
      'verdict-outcome-1': 'returned',
      'verdict-outcome-2': 'accepted',
    },
  );
}

/// The task graph of docs/design/task-graph.png
/// (test/layout/graphs/task.json).
Map<String, Object?> taskGraph() =>
    jsonDecode(File('test/layout/graphs/task.json').readAsStringSync())
        as Map<String, Object?>;

/// The model of docs/design/task-graph.png: session t9m4, whose one run went
/// round the coder twice and the reviewer once, and waits on `human-review`.
GraphModel taskModel() {
  final run = Journal(
    't9m4-run',
    node: 'admit',
    startedAt: 0,
    sessionId: 't9m4-session',
  );
  final outcomes = <String, Object?>{};
  var time = 0;
  for (final (node, outcome) in const [
    ('admit', 'fresh'),
    ('coder', null),
    ('coder-status', 'go-on'),
    ('coder', null),
    ('coder-status', 'done'),
    ('checks', null),
    ('checks-result', 'repair'),
    ('coder', null),
    ('coder-status', 'done'),
    ('checks', null),
    ('checks-result', 'pass'),
    ('reviewer', null),
    ('review-verdict', 'again'),
    ('reviewer', null),
    ('review-verdict', 'pass'),
  ]) {
    final output = outcome == null ? null : '$node-$time';
    if (output != null) outcomes[output] = outcome;
    run.step(node, time, end: time + 30, output: output);
    time += 31;
  }
  run.step('human-review', time);
  return modelOf(
    changes: changesOf([run], sessionId: 't9m4-session', graph: taskGraph()),
    outcomes: outcomes,
  );
}

/// Lets the feed reach the model, the canvas ask for the outcomes, and the
/// outcomes come back: a frame after each.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
