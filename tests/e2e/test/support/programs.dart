import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The root of the repository; `dart test` runs in `tests/e2e`.
final String repoRoot = p.normalize(p.absolute('..', '..'));

/// The `dart` that runs the tests.
final String dart = Platform.resolvedExecutable;

/// A fresh temporary directory, its real path, deleted after the test — or,
/// from `setUpAll`, after the tests of the file.
String tempDir() {
  final dir = Directory.systemTemp.createTempSync('nanoflow_e2e_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir.resolveSymbolicLinksSync();
}

/// Compiles the program [source] with `dart compile exe` to [exe]: a
/// signal must reach the program itself, not a `dart` that runs it.
Future<void> compile(String source, String exe) async {
  // Far longer than a compile takes.
  final compiled = await Process.run(dart, [
    'compile',
    'exe',
    source,
    '-o',
    exe,
  ]).timeout(const Duration(minutes: 2));
  expect(
    compiled.exitCode,
    0,
    reason: 'cannot compile $source: ${compiled.stdout}${compiled.stderr}',
  );
}

/// A program running as a process of its own, whose stdout and stderr are
/// collected; killed after the test if it still runs.
final class Running {
  Running._(this.process) {
    _closed = Future.wait([
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_line)
          .asFuture<void>(),
      process.stderr.transform(utf8.decoder).listen(err.write).asFuture<void>(),
    ]);
    process.exitCode.then((_) => _exited = true).ignore();
    addTearDown(() {
      if (!_exited) process.kill(ProcessSignal.sigkill);
    });
  }

  /// Starts [executable] with [arguments] in [dir], with [environment] added
  /// to this process's.
  static Future<Running> start(
    String executable,
    List<String> arguments, {
    String? dir,
    Map<String, String>? environment,
  }) async => Running._(
    await Process.start(
      executable,
      arguments,
      workingDirectory: dir,
      environment: environment,
    ),
  );

  final Process process;

  /// The lines it printed on stdout so far.
  final lines = <String>[];

  /// What it printed on stderr so far.
  final err = StringBuffer();

  final _first = Completer<String>();
  late final Future<void> _closed;
  bool _exited = false;

  void _line(String line) {
    lines.add(line);
    if (!_first.isCompleted) _first.complete(line);
  }

  /// The first line it prints on stdout: a session's id.
  Future<String> firstLine() async {
    await Future.any([_first.future, _closed]);
    if (!_first.isCompleted) fail('ended without printing a line: $err');
    return _first.future;
  }

  /// The code it exits with, once all it printed is collected.
  Future<int> get exitCode async {
    final code = await process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () => fail('has not exited: $err'),
    );
    await _closed;
    return code;
  }
}

/// What a program that ran to its end did: its exit code, stdout and
/// stderr.
typedef Outcome = ({int code, String out, String err});

/// Runs [executable] with [arguments] in [dir] to its end.
Future<Outcome> run(
  String executable,
  List<String> arguments, {
  String? dir,
  Map<String, String>? environment,
}) async {
  final running = await Running.start(
    executable,
    arguments,
    dir: dir,
    environment: environment,
  );
  final code = await running.exitCode;
  return (
    code: code,
    out: running.lines.map((line) => '$line\n').join(),
    err: '${running.err}',
  );
}

/// The session [sessionId] in the project directory [projectDir], to read:
/// the handle gives the session's lock up at once, so that a program can
/// still own the session.
Future<SessionHandle> sessionIn(String projectDir, String sessionId) async {
  final session = await FsStore(runsDirOf(projectDir)).openSession(sessionId);
  expect(session, isNotNull, reason: 'no session $sessionId in $projectDir');
  await session!.release();
  return session;
}

/// The names of the events of [session], in order.
Future<List<String>> eventNames(SessionHandle session) async => [
  for (final event in await session.events()) event.name,
];

/// What the log of [step] of [session] holds; `null` when it has none.
String? logOf(SessionHandle session, Step step) {
  final dir = Directory(p.join(session.dir, stepsDirName))
      .listSync()
      .singleWhere((entity) => idOfDirName(p.basename(entity.path)) == step.id);
  final log = File(p.join(dir.path, step.log));
  return log.existsSync() ? log.readAsStringSync() : null;
}

/// Every file under [dir], by its path relative to [dir], with what it
/// holds.
Map<String, String> filesUnder(String dir) => {
  for (final entity in Directory(dir).listSync(recursive: true))
    if (entity is File)
      p.relative(entity.path, from: dir): entity.readAsStringSync(),
};

/// The JSON object in the file [path].
Map<String, Object?> readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
