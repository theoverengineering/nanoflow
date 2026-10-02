// Fixtures written the way the store writes them (D2, D3), with plain
// `dart:io` and the models' `toJson`: the reader's tests must not depend on
// `nanoflow_store`.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_reader/nanoflow_reader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// 2026-09-20 14:03:11.470 UTC, the time of the README's example session.
final DateTime start = DateTime.utc(2026, 9, 20, 14, 3, 11, 470);

/// [start] moved on by [seconds].
DateTime at(int seconds) => start.add(Duration(seconds: seconds));

/// The graph a session holds: a session stores whatever map it is given.
const graph = <String, Object?>{
  'start': 'collect',
  'nodes': {
    'collect': {'command': 'nodes/collect/run.sh', 'then': 'is-empty'},
  },
};

/// How long a test waits for the feed before it fails.
const _patience = Duration(seconds: 10);

/// Why a test of a file that cannot be read is skipped, or `null`: root reads
/// any file, whatever its mode.
final String? skipAsRoot =
    (Process.runSync('id', ['-u']).stdout as String).trim() == '0'
    ? 'root can read a file with mode 000'
    : null;

/// Waits until [done] holds, looking every few milliseconds; fails the test
/// after a while.
Future<void> eventually(bool Function() done) async {
  final deadline = DateTime.now().add(_patience);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('waited too long');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// A fresh temporary directory, deleted after the test.
Future<String> tempDir() async {
  final dir = await Directory.systemTemp.createTemp('nanoflow_reader_test');
  addTearDown(() => dir.delete(recursive: true));
  return dir.path;
}

/// A `runs` directory that does not exist yet, in a fresh temporary
/// directory.
Future<String> newRunsDir() async => p.join(await tempDir(), 'runs');

/// Writes [json] to [path] pretty-printed with a trailing newline, under
/// `.<name>.tmp-<id>` renamed into place.
void writeJson(String path, Object? json) {
  final temporary = File(
    p.join(p.dirname(path), '.${p.basename(path)}.tmp-${newId()}'),
  );
  temporary.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(json)}\n',
  );
  temporary.renameSync(path);
}

/// Builds the directory [name] in [parent] whole: [build] fills
/// `<parent>/.tmp-<id>`, which is then renamed. Returns the built path.
String buildDir(String parent, String name, void Function(String dir) build) {
  final temporary = Directory(p.join(parent, '.tmp-${newId()}'))
    ..createSync(recursive: true);
  build(temporary.path);
  return temporary.renameSync(p.join(parent, name)).path;
}

/// Writes [session] of the graph [graphName] to [runsDir]; returns its
/// directory. Without [documents], the session has no `documents` directory.
String writeSession(
  String runsDir,
  Session session, {
  String graphName = 'review',
  DateTime? createdAt,
  bool documents = true,
}) => buildDir(
  runsDir,
  sessionDirName(graphName, createdAt ?? start, session.id),
  (dir) {
    writeJson(p.join(dir, sessionFileName), session.toJson());
    if (documents) Directory(p.join(dir, documentsDirName)).createSync();
  },
);

/// Writes [run] to [sessionDir], with [events] in its journal; returns its
/// directory.
String writeRun(
  String sessionDir,
  Run run, {
  required DateTime createdAt,
  List<Event> events = const [],
}) => buildDir(sessionDir, runDirName(createdAt, run.id), (dir) {
  writeJson(p.join(dir, runFileName), run.toJson());
  File(p.join(dir, eventsFileName)).writeAsStringSync(events.map(line).join());
  Directory(p.join(dir, stepsDirName)).createSync();
});

/// Writes [step] of the node [node] to the run directory [runDir]; returns
/// its directory.
String writeStep(
  String runDir,
  Step step, {
  required String node,
  required DateTime startedAt,
}) => buildDir(
  p.join(runDir, stepsDirName),
  stepDirName(startedAt, node, step.id),
  (dir) => writeJson(p.join(dir, stepFileName), step.toJson()),
);

/// Rewrites `step.json` in [stepDir] with [step].
void rewriteStep(String stepDir, Step step) =>
    writeJson(p.join(stepDir, stepFileName), step.toJson());

/// Writes [document] to the session directory [sessionDir].
void writeDocument(String sessionDir, Document document) => writeJson(
  p.join(sessionDir, documentsDirName, documentFileName(document.id)),
  document.toJson(),
);

/// The journal line of [event]: compact JSON and `\n`.
String line(Event event) => '${jsonEncode(event.toJson())}\n';

/// Appends [text] to the journal of the run in [runDir].
void append(String runDir, String text) =>
    File(p.join(runDir, eventsFileName))
        .writeAsStringSync(text, mode: FileMode.append, flush: true);

/// Appends [bytes] to the file at [path].
void appendBytes(String path, List<int> bytes) =>
    File(path).writeAsBytesSync(bytes, mode: FileMode.append, flush: true);

/// Cuts the file at [path] to [length] bytes.
void truncate(String path, int length) {
  final file = File(path).openSync(mode: FileMode.append);
  try {
    file.truncateSync(length);
  } finally {
    file.closeSync();
  }
}

/// A step of [runId] that has not finished, with its log in `command.log`.
Step newStep(String runId, {String? inputId}) => Step(
  id: newId(),
  runId: runId,
  inputId: inputId,
  outputId: null,
  log: logFileName,
);

/// The changes and errors a reader's feed gives, collected as they come.
final class Feed {
  /// Listens to the feed of a new reader of [graphName] in [runsDir] until
  /// the test ends.
  Feed(
    String runsDir, {
    String graphName = 'review',
    Duration pollInterval = const Duration(milliseconds: 20),
  }) : this.of(
         FsReader(
           runsDir: runsDir,
           graphName: graphName,
           pollInterval: pollInterval,
         ),
       );

  /// Listens to the feed of [reader] until the test ends.
  Feed.of(this.reader) {
    final subscription = reader.changes().listen(
      (change) {
        if (change case SessionAdded(:final session)
            when _markers.containsKey(session.id)) {
          _markers[session.id] = true;
        } else {
          changes.add(change);
        }
        _check();
      },
      onError: (Object error) {
        errors.add(error);
        _check();
      },
    );
    addTearDown(subscription.cancel);
  }

  final FsReader reader;

  /// Every change given so far, in order, without the markers of [settle].
  final List<Change> changes = [];

  /// Every error given so far.
  final List<Object> errors = [];

  /// Sessions [settle] wrote, by id: whether the feed has given them.
  final Map<String, bool> _markers = {};

  final List<({bool Function() done, Completer<void> completer})> _waiting = [];

  /// Waits until [done] holds; fails the test after a while.
  Future<void> until(bool Function() done) {
    if (done()) return Future.value();
    final completer = Completer<void>();
    _waiting.add((done: done, completer: completer));
    return completer.future.timeout(
      _patience,
      onTimeout: () => fail('the feed has not caught up; it gave $changes'),
    );
  }

  /// Waits until a change [matches] has come; returns it.
  Future<T> next<T extends Change>([bool Function(T change)? matches]) async {
    T? found;
    await until(() {
      for (final change in changes) {
        if (change is T && (matches == null || matches(change))) {
          found = change;
          return true;
        }
      }
      return false;
    });
    return found!;
  }

  /// Waits until the feed has given everything the sessions of the graph on
  /// disk hold now.
  ///
  /// Writes a marker session of the graph created in 1970 and waits for it:
  /// the scan that finds it has listed the sessions after this call, and went
  /// through those that are newer — every other — first. A second call waits
  /// for a scan that began after the one that gave the first marker had
  /// ended, so by then anything a scan gives again, or gives for a directory
  /// older than the marker, has come too.
  Future<void> settle() async {
    final id = newId();
    _markers[id] = false;
    writeSession(
      reader.runsDir,
      Session(id: id, graph: const {}),
      graphName: reader.graphName,
      createdAt: DateTime.utc(1970),
      documents: false,
    );
    await until(() => _markers[id]!);
  }

  /// The changes given since [mark], a length of [changes] taken earlier.
  List<Change> since(int mark) => changes.sublist(mark);

  void _check() {
    for (final waiting in [..._waiting]) {
      if (waiting.done()) {
        _waiting.remove(waiting);
        waiting.completer.complete();
      }
    }
  }
}

/// Collects the text of a [stepLog] stream as it comes.
final class LogText {
  LogText(Stream<String> log) {
    final subscription = log.listen((text) {
      chunks.add(text);
      for (final waiting in [..._waiting]) {
        if (waiting.done()) {
          _waiting.remove(waiting);
          waiting.completer.complete();
        }
      }
    }, onError: (Object error) => fail('the log gave an error: $error'));
    addTearDown(subscription.cancel);
  }

  /// The pieces of text given so far, in order.
  final List<String> chunks = [];

  final List<({bool Function() done, Completer<void> completer})> _waiting = [];

  /// Everything given so far.
  String get text => chunks.join();

  /// Waits until the text given so far is at least as long as [expected], and
  /// returns it.
  Future<String> untilLength(String expected) async {
    bool done() => text.length >= expected.length;
    if (!done()) {
      final completer = Completer<void>();
      _waiting.add((done: done, completer: completer));
      await completer.future.timeout(
        _patience,
        onTimeout: () => fail('the log has given only "$text"'),
      );
    }
    return text;
  }
}
