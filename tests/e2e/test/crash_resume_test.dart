// A workflow program (test/fixtures/held.dart) killed in an effect and taken on
// by another process; and a second process refused while one owns the
// session.
@Timeout(Duration(seconds: 90))
library;

import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/programs.dart';
import 'support/wait.dart';

/// held.dart, compiled once for the tests of this file.
late String held;

/// How many times the body of the effect [name] ran in the project directory
/// [dir].
int runsOf(String dir, String name) {
  final file = File(p.join(dir, '$name.runs'));
  return file.existsSync() ? file.lengthSync() : 0;
}

/// Starts held.dart in the project directory [dir], and waits until its
/// effect `inspect` runs; gives it and the id of its session.
Future<({Running program, String sessionId})> startUntilInspect(
  String dir,
) async {
  final program = await Running.start(held, [dir, 'change']);
  final sessionId = await program.firstLine();
  await waitFor('the effect inspect to run', () => runsOf(dir, 'inspect') == 1);
  return (program: program, sessionId: sessionId);
}

void main() {
  setUpAll(() async {
    held = p.join(tempDir(), 'held');
    await compile(p.join('test', 'fixtures', 'held.dart'), held);
  });

  test('killed with SIGKILL in an effect, its session is ended by --resume in '
      'another process: the effect that finished is taken from the journal, '
      'the one that was killed runs again in its record', () async {
    final dir = tempDir();
    final (:program, :sessionId) = await startUntilInspect(dir);

    program.process.kill(ProcessSignal.sigkill);
    expect(await program.exitCode, -ProcessSignal.sigkill.signalNumber);
    File(p.join(dir, 'go')).createSync();

    expect(await run(held, [dir, '--resume', sessionId]), (
      code: 0,
      out: '$sessionId\nchange collected, inspected, published\n',
      err: '',
    ));
    expect(
      [
        for (final name in ['collect', 'inspect', 'publish']) runsOf(dir, name),
      ],
      [1, 2, 1],
    );

    final session = await sessionIn(dir, sessionId);
    expect(await eventNames(session), [
      'session-started',
      'effect-started',
      'effect-finished',
      'effect-started',
      'session-resumed',
      'effect-started',
      'effect-finished',
      'effect-started',
      'effect-finished',
      'session-finished',
    ]);
    final effects = await session.effects();
    expect(
      [for (final effect in effects) effect.name],
      ['collect', 'inspect', 'publish'],
    );
    final state = replaySession(await session.events());
    expect(state.status, SessionStatus.finished);
    expect(
      [for (final effect in state.effects) (effect.effectId, effect.starts)],
      [(effects[0].id, 1), (effects[1].id, 2), (effects[2].id, 1)],
    );
    // The same binary ran both times: the graph is not taken again.
    final code = bytesHash(File(held).readAsBytesSync());
    expect(state.codes, [code, code]);
    expect(state.graphIds, isEmpty);
  });

  test('a second process cannot take on a session that a process runs: its '
      '--resume fails with SessionBusyException and writes nothing', () async {
    final dir = tempDir();
    final (:program, :sessionId) = await startUntilInspect(dir);
    final runs = runsDirOf(dir);
    final before = filesUnder(runs);

    final second = await run(held, [dir, '--resume', sessionId]);
    expect(second.code, isNot(0));
    expect(second.out, isEmpty);
    expect(second.err, contains('${SessionBusyException(sessionId)}'));
    expect(filesUnder(runs), before);
    expect(runsOf(dir, 'inspect'), 1);

    File(p.join(dir, 'go')).createSync();
    expect(await program.exitCode, 0, reason: '${program.err}');
    expect(program.lines, [
      sessionId,
      'change collected, inspected, published',
    ]);
    final session = await sessionIn(dir, sessionId);
    expect(
      replaySession(await session.events()).status,
      SessionStatus.finished,
    );
  });
}
