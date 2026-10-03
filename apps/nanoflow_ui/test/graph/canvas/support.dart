// Graph screen models of the graph files in test/layout/graphs/, for the
// canvas and screen tests.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/graph_model.dart';
import 'package:nanoflow_ui/state/outcomes.dart';
import 'package:nanoflow_ui/state/session_feed.dart';
import 'package:nanoflow_ui/state/step_files.dart';

import '../../layout/support.dart' show loadGraphFile;
import '../../state/support.dart';

/// The size of the canvas in docs/design/graph.html: the window less the
/// sessions column, the header and the `Logs` panel.
const reviewCanvas = Size(1440 - 272, 900 - 48 - 280);

/// The graph file `test/layout/graphs/<name>.graph.json`.
GraphFile graphFileNamed(String name) => loadGraphFile(name);

/// A graph screen's model of the graph file [graph] at [file] (by default
/// the release fixture of describe), fed [changes], then what [more]
/// gives. Sessions' documents are [documents]. The graph is opened after
/// every session of the tests, so the newest is selected.
GraphModel modelOf({
  GraphFile? graph,
  String file = '/nowhere/$graphFileName',
  List<Change> changes = const [],
  Stream<Change> more = const Stream.empty(),
  Map<String, Object?> documents = const {},
  bool noGraph = false,
  StepFiles? files,
}) {
  final model = ownedModel(
    graph: graph,
    file: file,
    changes: changes,
    more: more,
    documents: documents,
    noGraph: noGraph,
    files: files,
  );
  addTearDown(model.dispose);
  return model;
}

/// [modelOf] for whoever disposes it: the graph screen disposes its model.
/// Without [graph], the release fixture of describe; no graph file read at
/// all when [noGraph]. Steps' logs and documents are [files].
GraphModel ownedModel({
  GraphFile? graph,
  String file = '/nowhere/$graphFileName',
  List<Change> changes = const [],
  Stream<Change> more = const Stream.empty(),
  Map<String, Object?> documents = const {},
  bool noGraph = false,
  StepFiles? files,
}) {
  final graphFile = FixedGraphFile(
    noGraph ? null : graph ?? graphFileNamed('release'),
    file,
  );
  return GraphModel(
    graphFile: graphFile,
    freshness: FixedFreshness(graphFile),
    feed: SessionFeed(_concat(Stream.fromIterable(changes), more)),
    outcomes: Outcomes((_, documentId) async => documents[documentId]),
    files: files ?? FakeFiles(),
    now: () => at(100000),
  );
}

Stream<T> _concat<T>(Stream<T> first, Stream<T> then) async* {
  yield* first;
  yield* then;
}

/// The graph file of [model], as the tests set it.
FixedGraphFile graphFileOf(GraphModel model) =>
    model.graphFile as FixedGraphFile;

/// Lets the feed reach the model and the canvas follow: a frame after
/// each.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
