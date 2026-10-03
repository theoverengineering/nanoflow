import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:nanoflow/src/context.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `h(s)` of decision D1, computed here rather than taken from the library:
/// the first 16 hex digits of the sha256 of [s] in UTF-8.
String h(String s) =>
    sha256.convert(utf8.encode(s)).toString().substring(0, 16);

/// A fresh temporary directory, deleted after the test.
Future<String> tempDir() async {
  final dir = await Directory.systemTemp.createTemp('nanoflow_test');
  addTearDown(() => dir.delete(recursive: true));
  return dir.path;
}

/// The ids of the sessions in the project directory [projectDir], sorted.
List<String> sessionIds(String projectDir) {
  final runs = Directory(runsDirOf(projectDir));
  if (!runs.existsSync()) return const [];
  return [
    for (final entity in runs.listSync()) ?idOfDirName(p.basename(entity.path)),
  ]..sort();
}

/// The directory of the session [sessionId] of [projectDir].
String sessionDirOf(String projectDir, String sessionId) => [
  for (final entity in Directory(runsDirOf(projectDir)).listSync())
    if (idOfDirName(p.basename(entity.path)) == sessionId) entity.path,
].single;

/// Every file under [dir], by its path relative to [dir], with what it
/// holds.
///
/// With [withOwner] false, but for `.owner.lock`: it tells who holds the
/// session right now, which changes when the process lets the session go, and
/// is not what the session writes. Reading it in the process that owns the
/// session closes a descriptor of it, which drops that process's lock, so a
/// snapshot of a session that runs is taken without it.
Map<String, String> filesUnder(String dir, {bool withOwner = true}) => {
  for (final entity in Directory(dir).listSync(recursive: true))
    if (entity is File &&
        (withOwner || p.basename(entity.path) != ownerLockFileName))
      p.relative(entity.path, from: dir): entity.readAsStringSync(),
};

/// The names of the events in the journal of the session [sessionId] of
/// [projectDir], read without owning the session: it may still run.
List<String> eventNamesOf(String projectDir, String sessionId) => [
  for (final line in File(
    p.join(sessionDirOf(projectDir, sessionId), eventsFileName),
  ).readAsLinesSync())
    (jsonDecode(line) as Map<String, Object?>)['event']! as String,
];

/// Waits until [condition] holds, looking every 10 ms; fails, naming [what]
/// it waited for, after [within].
Future<void> until(
  bool Function() condition,
  String what, {
  Duration within = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(within);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('waited in vain for $what');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// The session [sessionId] of [projectDir] opened for reading; let go after
/// the test.
Future<SessionHandle> openSession(String projectDir, String sessionId) async {
  final handle = await FsStore(runsDirOf(projectDir)).openSession(sessionId);
  addTearDown(() => handle?.release());
  return handle!;
}

/// The only session of [projectDir], opened for reading.
Future<SessionHandle> onlySession(String projectDir) async {
  final ids = sessionIds(projectDir);
  expect(ids, hasLength(1));
  return openSession(projectDir, ids.single);
}

/// The known events of the session of [handle], in order.
Future<List<KnownEvent>> eventsOf(SessionHandle handle) async => [
  for (final event in await handle.events()) event as KnownEvent,
];

/// What the log of the step [name] of the session of [handle] holds; `null`
/// when the step has no log file.
Future<String?> logOfStep(SessionHandle handle, String name) async {
  final step = (await handle.steps()).singleWhere((s) => s.name == name);
  final dir = Directory(p.join(handle.dir, stepsDirName))
      .listSync()
      .singleWhere((entity) => p.basename(entity.path).endsWith(step.id));
  final log = File(p.join(dir.path, step.log));
  return log.existsSync() ? log.readAsStringSync() : null;
}

/// What another process that tries to own the session [sessionId] of
/// [projectDir] finds: `busy` while this one owns it, `opened` when not.
Future<String> ownerCheck(String projectDir, String sessionId) async {
  final result = await Process.run(Platform.resolvedExecutable, [
    p.join('test', 'fixtures', 'open_session.dart'),
    runsDirOf(projectDir),
    sessionId,
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return (result.stdout as String).trim();
}

/// The place of the line that ends with the comment `// <marker>` in the
/// file of the code that calls this: its URI as stack traces print it and
/// the line, `file:///…/test/flow_test.dart:12`.
String placeOfMarker(String marker) {
  final caller = StackTrace.current.toString().split('\n')[1];
  final file = RegExp(r'\((.+?):\d+(?::\d+)?\)$').firstMatch(caller)!.group(1)!;
  final lines = File.fromUri(Uri.parse(file)).readAsLinesSync();
  final matching = [
    for (final (i, line) in lines.indexed)
      if (line.endsWith('// $marker')) i + 1,
  ];
  expect(matching, hasLength(1), reason: 'marker $marker in $file');
  return '$file:${matching.single}';
}

// Step keys without files: the prototype's `Flow` (prototypes/step_keys) on
// the library's KeyedZone.

late Random random;

/// An ordinary await that is not a step, of a random length.
Future<void> pause() =>
    Future.delayed(Duration(milliseconds: random.nextInt(10)));

Future<T> work<T>(T value) async {
  await pause();
  return value;
}

/// What a workflow ended with: wrong when a copy got another's results.
late String note;

/// Runs workflows in a [KeyedZone] and keeps what their steps return by key;
/// given a [journal], a step whose key is there returns the saved result
/// without running.
final class Keyed {
  Keyed({this.journal = const {}});

  /// Saved results by key: what a run before the crash completed.
  final Map<String, Object?> journal;

  /// What this run completed live, by key.
  final record = <String, Object?>{};

  /// The `after` of every step called, by its key.
  final after = <String, String?>{};

  final _zone = KeyedZone();

  Future<void> run(Future<void> Function(Keyed f) workflow) =>
      _zone.run(() => workflow(this));

  Future<T> step<T>(String name, Future<T> Function() body) =>
      _zone.step(name, (step) {
        after[step.key] = step.after;
        if (journal.containsKey(step.key)) {
          return Future<T>.value(journal[step.key] as T);
        }
        return step.runBody(body).then((value) {
          record[step.key] = value;
          return value;
        });
      });
}

/// Tests that [workflow] gives the same keys whatever the timing, and that
/// after a crash at any point every copy gets its own saved results and only
/// the steps that were not saved run again.
void checkWorkflow(String title, Future<void> Function(Keyed f) workflow) {
  group(title, () {
    late Keyed first;
    late String expected;

    setUp(() async {
      random = Random(1);
      first = Keyed();
      await first.run(workflow);
      expected = note;
    });

    test('gives the same keys whatever the timing', () async {
      final keys = first.record.keys.toSet();
      for (var seed = 2; seed < 22; seed++) {
        random = Random(seed);
        final other = Keyed();
        await other.run(workflow);
        expect(other.record.keys.toSet(), keys, reason: 'seed $seed');
        expect(other.after, first.after, reason: 'seed $seed');
      }
    });

    test('gives every copy its own saved results after a crash and runs only '
        'the steps that were not saved', () async {
      final keys = first.record.keys.toList();
      for (var seed = 2; seed < 22; seed++) {
        random = Random(seed);
        final saved = (keys.toList()..shuffle(random))
            .take(1 + random.nextInt(max(1, keys.length - 1)))
            .toSet();
        final resumed = Keyed(
          journal: {for (final k in saved) k: first.record[k]},
        );
        await resumed.run(workflow);
        expect(note, expected, reason: 'seed $seed, saved $saved');
        expect(
          resumed.record.keys.toSet(),
          keys.toSet().difference(saved),
          reason: 'seed $seed, saved $saved',
        );
      }
    });
  });
}
