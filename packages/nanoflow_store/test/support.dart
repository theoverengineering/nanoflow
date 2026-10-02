import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// 2026-09-20 14:03:11.470 UTC, the time of the README's example session.
final DateTime start = DateTime.utc(2026, 9, 20, 14, 3, 11, 470);

/// A clock that returns [from] and then moves by [tick] on every reading.
Clock tickingClock({
  DateTime? from,
  Duration tick = const Duration(seconds: 1),
}) {
  var now = from ?? start;
  return () {
    final time = now;
    now = now.add(tick);
    return time;
  };
}

/// A fresh temporary directory, deleted after the test.
Future<String> tempDir() async {
  final dir = await Directory.systemTemp.createTemp('nanoflow_store_test');
  addTearDown(() => dir.delete(recursive: true));
  return dir.path;
}

/// The names of the entries in [dir], sorted.
List<String> names(String dir) =>
    [for (final entity in Directory(dir).listSync()) p.basename(entity.path)]
      ..sort();

/// Every path under [dir] whose name starts with `.`, but the lock file of
/// the engine that drives a session: what is left of writes.
List<String> dotEntries(String dir) => [
  for (final entity in Directory(dir).listSync(recursive: true))
    if (p.basename(entity.path) case final name
        when name.startsWith('.') && name != '.engine.lock')
      entity.path,
];

/// The one entry in [dir] whose name matches [pattern]: its path, and the id
/// the pattern's first group captures.
({String path, String id}) only(String dir, String pattern) {
  final regExp = RegExp('^$pattern\$');
  final matching = names(dir).where(regExp.hasMatch).toList();
  expect(matching, hasLength(1), reason: 'in $dir: ${names(dir)}');
  return (
    path: p.join(dir, matching.single),
    id: regExp.firstMatch(matching.single)!.group(1)!,
  );
}

/// A pattern that captures a lowercase UUID.
const anId = r'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})';

/// The text of the file at [path].
String read(String path) => File(path).readAsStringSync();

/// A graph from the README, cut down: what a session stores is whatever map
/// it is given.
const graph = <String, Object?>{
  'start': 'collect',
  'nodes': {
    'collect': {
      'command': 'nodes/collect/run.sh',
      'in': {r'$ref': '#/Request'},
      'then': 'is-empty',
    },
  },
};

/// The session.json of [sessionId] for [graph].
String sessionJson(String sessionId) =>
    '''
{
  "id": "$sessionId",
  "graph": {
    "start": "collect",
    "nodes": {
      "collect": {
        "command": "nodes/collect/run.sh",
        "in": {
          "\$ref": "#/Request"
        },
        "then": "is-empty"
      }
    }
  }
}
''';

/// A new session of graph `review` in a fresh `runs` directory.
Future<SessionHandle> newSession({
  Clock? clock,
  List<StartNode> startNodes = const [(node: 'collect', takesInput: true)],
  ({Object? value})? input = const (value: {'branch': 'main'}),
}) async {
  final store = FsStore(
    p.join(await tempDir(), 'runs'),
    clock: clock ?? tickingClock(),
  );
  return store.createSession(
    graphName: 'review',
    graph: graph,
    startNodes: startNodes,
    input: input,
  );
}

/// The directory of the run [runId] in the session of [handle].
String runDir(SessionHandle handle, String runId) =>
    only(handle.dir, '[0-9T-]{23}-($runId)').path;

/// The directory of the step [stepId] of the run [runId].
String stepDir(SessionHandle handle, String runId, String stepId) =>
    only(p.join(runDir(handle, runId), 'steps'), '.*-($stepId)').path;

/// The node the run [runId] started at.
Future<String> firstNode(SessionHandle handle, String runId) async =>
    ((await handle.events(runId)).first as RunStarted).node;
