@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/engine.dart';

/// Whether the process [pid] runs.
bool isAlive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

/// The pid in the file [name] in [dir], once it is there. The process is
/// killed when the test ends, if it still runs.
Future<int> pidIn(String dir, String name) async {
  final file = File(p.join(dir, name));
  await waitFor(file.existsSync);
  final pid = int.parse(file.readAsStringSync().trim());
  addTearDown(() => Process.killPid(pid, ProcessSignal.sigkill));
  file.deleteSync();
  return pid;
}

void main() {
  setUpAll(compileEngine);

  test('the engine killed with SIGKILL during a step of a Dart graph program: '
      'the step stops with it, and --resume runs the same step again and '
      'ends the session', () async {
    final dir = copyToTemp([p.join('test', 'fixtures', 'held.dart')]);
    final program = dartRun('held.dart');
    final engine = await EngineProcess.start([
      'run',
      '--',
      ...program,
    ], dir: dir);
    final call = await pidIn(dir, 'call.pid');
    final command = await pidIn(dir, 'command.pid');

    engine.process.kill(ProcessSignal.sigkill);
    expect(await engine.exitCode, -ProcessSignal.sigkill.signalNumber);
    // The end of its stdin stops the call, and the call stops its command.
    await waitFor(() => !isAlive(call) && !isAlive(command));

    final id = (await engine.out).trim();
    final session = await sessionIn(dir, id);
    final [run] = await session.runs();
    expect(await journal(session, run.id), [
      'run-started hold',
      'step-started hold',
    ]);
    final held = (await session.events(run.id)).last as StepStarted;

    File(p.join(dir, 'release')).createSync();
    final resumed = await nanoflow([
      'run',
      '--resume',
      id,
      '--',
      ...program,
    ], dir: dir);
    expect(resumed.code, 0, reason: resumed.err);
    expect(resumed.out, '$id\n');
    expect(await journal(session, run.id), [
      'run-started hold',
      'step-started hold',
      'step-started hold',
      'step-finished 0',
      'step-started done',
      'step-finished 0',
      'run-finished',
    ]);
    final events = await session.events(run.id);
    expect(
      [for (final event in events.whereType<StepStarted>()) event.stepId]
          .take(2),
      [held.stepId, held.stepId],
    );
    final [first, second] = await session.steps(run.id);
    expect(first.id, held.stepId);
    expect(logOf(session, first), 'holding\nholding\n');
    expect(logOf(session, second), 'released\n');
  });
}
