import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// 2026-10-03 10:00:00.482 UTC, the time of the spec's example session.
final DateTime start = DateTime.utc(2026, 10, 3, 10, 0, 0, 482);

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
/// the process that owns a session: what is left of writes.
List<String> dotEntries(String dir) => [
  for (final entity in Directory(dir).listSync(recursive: true))
    if (p.basename(entity.path) case final name
        when name.startsWith('.') && name != '.owner.lock')
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

/// The code hash a session's `session-started` holds in these tests.
const code = 'sha256:7d3e9f0c';

/// A graph file, cut down: what a session stores is whatever map it is
/// given.
const graph = <String, Object?>{
  'format': 2,
  'workflows': ['lib/review.dart#review'],
};

/// The session.json of [sessionId] for [graph] and [inputId].
String sessionJson(String sessionId, {required String? inputId}) =>
    '''
{
  "id": "$sessionId",
  "workflow": "review",
  "graph": {
    "format": 2,
    "workflows": [
      "lib/review.dart#review"
    ]
  },
  "inputId": ${inputId == null ? 'null' : '"$inputId"'}
}
''';

/// A new session of workflow `review` in a fresh `runs` directory.
Future<FsSession> newSession({
  Clock? clock,
  ({Object? value})? input = const (value: {'branch': 'main'}),
}) async {
  final store = FsStore(
    p.join(await tempDir(), 'runs'),
    clock: clock ?? tickingClock(),
  );
  return store.createSession(
    workflow: 'review',
    graph: graph,
    input: input,
    code: code,
  );
}

/// A new effect of [handle] named [name], with a key made of it.
Future<Effect> newEffect(
  FsSession handle, {
  String name = 'collect',
  String? after,
}) => handle.createEffect(
  name: name,
  key: '$name#1@e3b0c44298fc1c14',
  after: after,
  place: 'lib/review.dart:12',
);

/// The directory of the effect [effectId] in the session of [handle].
String effectDir(FsSession handle, String effectId) =>
    only(p.join(handle.dir, 'effects'), '.*-($effectId)').path;

/// The journal of the session of [handle].
String journal(FsSession handle) => p.join(handle.dir, 'log.jsonl');

/// What another process that tries to own the session [sessionId] of
/// [runsDir] finds: `busy` while this one owns it, `opened` when not.
Future<String> ownerCheck(String runsDir, String sessionId) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    p.join('test', 'fixtures', 'open_session.dart'),
    runsDir,
    sessionId,
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return (result.stdout as String).trim();
}
