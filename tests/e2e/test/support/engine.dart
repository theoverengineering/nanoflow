import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The root of the repository; `dart test` runs in `tests/e2e`.
final String repoRoot = p.normalize(p.absolute('..', '..'));

/// The `nanoflow` executable that [compileEngine] made for this test file.
late final String nanoflowExe;

/// Compiles `apps/nanoflow_cli/bin/nanoflow.dart` once for this test file
/// into a temporary directory, deleted after it: a signal must reach the
/// engine itself, not a `dart` wrapper. Call it from `setUpAll`.
Future<void> compileEngine() async {
  final dir = Directory.systemTemp.createTempSync('nanoflow_e2e_exe_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final exe = p.join(dir.path, 'nanoflow');
  // Far longer than a compile takes, and far shorter than the 12 minutes
  // the test package gives a setUpAll.
  final compiled = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'exe',
    p.join(repoRoot, 'apps', 'nanoflow_cli', 'bin', 'nanoflow.dart'),
    '-o',
    exe,
  ]).timeout(const Duration(minutes: 3));
  if (compiled.exitCode != 0) {
    throw StateError('cannot compile nanoflow: ${compiled.stderr}');
  }
  nanoflowExe = exe;
}

/// Copies [files] into a fresh temporary directory, deleted after the test,
/// and gives the directory. Sessions of a graph program go to `runs` next to
/// its file: a copy keeps them out of the repository.
String copyToTemp(List<String> files) {
  final dir = Directory.systemTemp.createTempSync('nanoflow_e2e_');
  addTearDown(() => dir.deleteSync(recursive: true));
  for (final file in files) {
    File(file).copySync(p.join(dir.path, p.basename(file)));
  }
  return dir.path;
}

/// The graph program [file] run by `dart run`, as the engine is given it.
///
/// A copy outside the workspace has no packages of its own: it gets the
/// workspace's.
List<String> dartRun(String file) => [
  Platform.resolvedExecutable,
  'run',
  '--packages=${p.join(repoRoot, '.dart_tool', 'package_config.json')}',
  file,
];

/// `nanoflow` running as a process of its own, in [EngineProcess.start]'s
/// directory; what it prints is collected. It is killed when the test ends,
/// if it still runs.
final class EngineProcess {
  EngineProcess._(this.process)
    : out = process.stdout.transform(utf8.decoder).join(),
      err = process.stderr.transform(utf8.decoder).join() {
    var exited = false;
    process.exitCode.then((_) => exited = true).ignore();
    addTearDown(() {
      if (!exited) process.kill(ProcessSignal.sigkill);
    });
  }

  /// Starts `nanoflow` with [args] in [dir], and writes [stdin] to it and
  /// closes it.
  static Future<EngineProcess> start(
    List<String> args, {
    required String dir,
    String stdin = '',
  }) async {
    final process = await Process.start(
      nanoflowExe,
      args,
      workingDirectory: dir,
    );
    process.stdin.write(stdin);
    unawaited(process.stdin.close());
    return EngineProcess._(process);
  }

  final Process process;

  /// All it prints on stdout and on stderr, once it has exited.
  final Future<String> out;
  final Future<String> err;

  /// The code it exits with; fails the test if that takes too long.
  Future<int> get exitCode => process.exitCode.timeout(
    const Duration(minutes: 2),
    onTimeout: () => fail('nanoflow has not exited'),
  );
}

/// What a finished `nanoflow` did: its exit code, stdout and stderr.
typedef Outcome = ({int code, String out, String err});

/// Runs `nanoflow` with [args] in [dir], with [stdin], to its end.
Future<Outcome> nanoflow(
  List<String> args, {
  required String dir,
  String stdin = '',
}) async {
  final engine = await EngineProcess.start(args, dir: dir, stdin: stdin);
  final code = await engine.exitCode;
  return (code: code, out: await engine.out, err: await engine.err);
}

/// The session [id] that `nanoflow run` made of the graph program in [dir],
/// to read: the handle gives the session's lock up at once, so that an
/// engine can still drive the session.
Future<SessionHandle> sessionIn(String dir, String id) async {
  final session = await FsStore(p.join(dir, runsDirName)).openSession(id);
  expect(session, isNotNull, reason: 'no session $id in $dir');
  await session!.release();
  return session;
}

/// The journal of the run [runId], an event a line: `step-started a`,
/// `step-finished 0`, `run-failed exited with code 3`.
Future<List<String>> journal(SessionHandle session, String runId) async => [
  for (final event in await session.events(runId))
    switch (event) {
      RunStarted(:final node) => 'run-started $node',
      StepStarted(:final node) => 'step-started $node',
      StepFinished(:final exitCode) => 'step-finished $exitCode',
      RunSplit() => 'run-split',
      RunFinished() => 'run-finished',
      RunFailed(:final error) => 'run-failed $error',
      UnknownEvent(:final json) => 'unknown $json',
    },
];

/// The command log of [step] of [session].
String logOf(SessionHandle session, Step step) {
  final run = _dirOf(session.dir, step.runId);
  final dir = _dirOf(p.join(run, stepsDirName), step.id);
  return File(p.join(dir, step.log!)).readAsStringSync();
}

/// The directory in [parent] whose name ends with [id].
String _dirOf(String parent, String id) =>
    Directory(parent)
        .listSync()
        .singleWhere((entity) => entity.path.endsWith(id))
        .path;
