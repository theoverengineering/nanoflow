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

/// A current graph, its errors and its problems as the test sets them; no
/// programs are started.
final class FixedSource extends GraphSource {
  FixedSource(this._graph)
    : super(file: '/nowhere/review.yaml', shell: Shell());

  Graph? _graph;
  List<String> _errors = const [];
  SourceProblem? _programProblem;
  String? _checkProblem;
  bool _fileMissing = false;

  /// Whether the source has been disposed.
  bool disposed = false;

  @override
  Graph? get graph => _graph;

  /// A new description passed check: [graph] is the current graph now.
  set graph(Graph? graph) {
    _graph = graph;
    notifyListeners();
  }

  @override
  List<String> get errors => _errors;

  set errors(List<String> errors) {
    _errors = errors;
    notifyListeners();
  }

  @override
  SourceProblem? get programProblem => _programProblem;

  set programProblem(SourceProblem? problem) {
    _programProblem = problem;
    notifyListeners();
  }

  @override
  String? get checkProblem => _checkProblem;

  set checkProblem(String? problem) {
    _checkProblem = problem;
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

/// A graph screen's model fed [changes], then what [more] gives, whose fork
/// outputs hold [outcomes], with [current] as the current graph. The graph
/// is opened after everything in the mockups, so their sessions are
/// selected.
GraphModel modelOf({
  List<Change> changes = const [],
  Stream<Change> more = const Stream.empty(),
  Map<String, Object?> outcomes = const {},
  Graph? current,
  FakeFiles? files,
}) {
  final model = ownedModel(
    changes: changes,
    more: more,
    outcomes: outcomes,
    current: current,
    files: files,
  );
  addTearDown(model.dispose);
  return model;
}

/// [modelOf] for whoever disposes it: the graph screen disposes its model.
/// The steps' logs and documents are [files]; the graph is opened at
/// [openedAt], by default after everything in the mockups of graph.png.
GraphModel ownedModel({
  List<Change> changes = const [],
  Stream<Change> more = const Stream.empty(),
  Map<String, Object?> outcomes = const {},
  Graph? current,
  FakeFiles? files,
  DateTime? openedAt,
}) => GraphModel(
  source: FixedSource(current),
  feed: SessionFeed(_concat(Stream.fromIterable(changes), more)),
  outcomes: Outcomes((_, documentId) async => outcomes[documentId]),
  files: files ?? FakeFiles(),
  now: () => openedAt ?? at(100000),
);

Stream<T> _concat<T>(Stream<T> first, Stream<T> then) async* {
  yield* first;
  yield* then;
}

/// The outcomes of the forks in [Mockup].
const reviewOutcomes = <String, Object?>{
  'is-empty-outcome': false,
  'verdict-outcome-1': 'returned',
  'verdict-outcome-2': 'accepted',
};

/// The model of docs/design/graph.png: session a1b2, run e5f6 and its step
/// on `notify` selected; [current] is the current graph.
GraphModel reviewModel({Graph? current}) {
  final mockup = Mockup();
  return modelOf(
    current: current,
    changes: changesOf([mockup.k7f2, mockup.c3d4, mockup.e5f6]),
    outcomes: reviewOutcomes,
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
