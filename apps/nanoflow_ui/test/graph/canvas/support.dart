// Graph screen models of the graph files in test/layout/graphs/, for the
// canvas and screen tests.

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/effect_files.dart';
import 'package:nanoflow_ui/state/graph_model.dart';
import 'package:nanoflow_ui/state/outcomes.dart';
import 'package:nanoflow_ui/state/session_feed.dart';
import 'package:nanoflow_ui/widgets/doc_text.dart';

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
  String file = '/nowhere/lib/release.graph.json',
  List<Change> changes = const [],
  Stream<Change> more = const Stream.empty(),
  Map<String, Object?> documents = const {},
  bool noGraph = false,
  EffectFiles? files,
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
/// all when [noGraph]. Effects' logs and documents are [files].
GraphModel ownedModel({
  GraphFile? graph,
  String file = '/nowhere/lib/release.graph.json',
  List<Change> changes = const [],
  Stream<Change> more = const Stream.empty(),
  Map<String, Object?> documents = const {},
  bool noGraph = false,
  EffectFiles? files,
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

/// The release fixture as docs/design/code-first/function-frames.html has
/// it: publish() uploads by calling upload(), which signs by calling
/// sign() before it puts.
GraphFile framesGraphFile() {
  final json = graphFileNamed('release').toJson();
  final functions = json['functions']! as Map<String, Object?>;
  Map<String, Object?> effect(String id, String name, int line) => {
    'id': id,
    'kind': 'effect',
    'name': name,
    'place': 'lib/publish.dart:$line',
    'doc': null,
  };
  Map<String, Object?> call(String id, String function, int line) => {
    'id': id,
    'kind': 'call',
    'functions': ['lib/publish.dart#$function'],
    'place': 'lib/publish.dart:$line',
  };
  Map<String, Object?> chain(List<Map<String, Object?>> nodes) => {
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
  final publish = functions['lib/publish.dart#publish']! as Map;
  final body = publish['body']! as Map;
  (body['nodes']! as List)[0] = call('1', 'upload', 12);
  functions['lib/publish.dart#upload'] = {
    'name': 'upload',
    'place': 'lib/publish.dart:20',
    'doc': null,
    'body': chain([call('1', 'sign', 21), effect('2', 'put', 22)]),
  };
  functions['lib/publish.dart#sign'] = {
    'name': 'sign',
    'place': 'lib/publish.dart:25',
    'doc': null,
    'body': chain([effect('1', 'hash', 26), effect('2', 'signature', 27)]),
  };
  return GraphFile.fromJson(json);
}

/// [file] with the docs of [functions], by id, and of [effects], by
/// `<function id>/<node id>` of an effect node of a function's body.
GraphFile documented(
  GraphFile file, {
  Map<String, String> functions = const {},
  Map<String, String> effects = const {},
}) {
  final json = file.toJson();
  for (final MapEntry(key: id, value: function)
      in (json['functions']! as Map<String, Object?>).entries) {
    final entry = function! as Map<String, Object?>;
    entry['doc'] = functions[id] ?? entry['doc'];
    final body = entry['body']! as Map<String, Object?>;
    for (final node in body['nodes']! as List<Object?>) {
      final map = node! as Map<String, Object?>;
      if (effects['$id/${map['id']}'] case final doc?) map['doc'] = doc;
    }
  }
  return GraphFile.fromJson(json);
}

/// Rests the mouse — [mouse], or a new one — on the middle of [finder]
/// until a doc tooltip shows; returns the mouse to move on with.
Future<TestGesture> hover(
  WidgetTester tester,
  Finder finder, [
  TestGesture? mouse,
]) async {
  final pointer =
      mouse ?? await tester.createGesture(kind: PointerDeviceKind.mouse);
  if (mouse == null) {
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
  }
  await pointer.moveTo(tester.getCenter(finder));
  await tester.pump(DocTooltip.wait);
  await tester.pump(const Duration(milliseconds: 300));
  return pointer;
}
