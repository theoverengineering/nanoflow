@TestOn('mac-os')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';
import 'package:nanoflow/src/flow.dart';
import 'package:nanoflow/src/owner.dart' show currentOwner;
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_process/nanoflow_process.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

/// Completed when the effect of the session of each input is running.
final entered = <String, Completer<void>>{};

/// What the effect of the session of each input waits for.
final gates = <String, Completer<void>>{};

/// Makes the session of [who] one whose effect waits for its gate, and lets
/// the effect go after the test, whatever the test did.
void hold(String who) {
  final gate = Completer<void>();
  addTearDown(() {
    if (!gate.isCompleted) gate.complete();
  });
  entered[who] = Completer();
  gates[who] = gate;
}

/// Waits in the effect `hold` until the gate of [who] opens.
Future<String> _hold(Flow f, String who) => f.effect('hold', () async {
  entered[who]!.complete();
  await gates[who]!.future;
  return 'held $who';
});

/// A session that waits in its effect `hold` until its gate opens.
Future<String> held(Flow f, String who) => _hold(f, who);

/// A session that fails once its effect `hold` has ended.
Future<String> failsAfterHold(Flow f, String who) async {
  await _hold(f, who);
  throw StateError('no way');
}

/// What `.owner.lock` of the session [sessionId] of [projectDir] holds.
///
/// Reading it closes a descriptor of the file in the process that owns the
/// session, and POSIX then drops this process's lock on it: a test that has
/// read the file must not assert that the session is still locked.
String lockOf(String projectDir, String sessionId) =>
    File(p.join(sessionDirOf(projectDir, sessionId), ownerLockFileName))
        .readAsStringSync();

/// What this process records as the owner: its pid and the start time the
/// OS gives for it, in the form of `.owner.lock`.
final recordOfThisProcess = jsonEncode(
  Owner(pid: pid, started: MacProcesses().startOf(pid)).toJson(),
);

void main() {
  test('this process has a start time from the OS, which the record '
      'carries', () {
    expect(MacProcesses().startOf(pid), isNotNull);
    expect(
      recordOfThisProcess,
      matches(
        RegExp(
          r'^\{"pid":\d+,"started":"'
          r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z"\}$',
        ),
      ),
    );
  });

  test('the owner of the process is its pid and the start time the OS '
      'gives, worked out once', () {
    final owner = currentOwner();

    expect(owner, Owner(pid: pid, started: MacProcesses().startOf(pid)));
    expect(owner.started, isNotNull);
    expect(identical(currentOwner(), owner), isTrue);
  });

  test('a session that runs records the pid and the start time of the process '
      'in .owner.lock', () async {
    final dir = await tempDir();
    hold('runs');

    final session = await Flow(directory: dir).startWorkflow(held, 'runs');
    await entered['runs']!.future;

    expect(lockOf(dir, session.id), recordOfThisProcess);
    gates['runs']!.complete();
    expect(await session.result, 'held runs');
  });

  test('a session that finished leaves .owner.lock empty', () async {
    final dir = await tempDir();
    hold('finishes');
    final session = await Flow(directory: dir).startWorkflow(held, 'finishes');
    await entered['finishes']!.future;
    expect(lockOf(dir, session.id), recordOfThisProcess);

    gates['finishes']!.complete();
    await session.result;

    expect(lockOf(dir, session.id), isEmpty);
  });

  test('a session that failed leaves .owner.lock empty', () async {
    final dir = await tempDir();
    hold('fails');
    final session = await Flow(directory: dir)
        .startWorkflow(failsAfterHold, 'fails');
    await entered['fails']!.future;
    expect(lockOf(dir, session.id), recordOfThisProcess);

    gates['fails']!.complete();
    await expectLater(session.result, throwsA(isA<StateError>()));

    expect(lockOf(dir, session.id), isEmpty);
  });

  test('a session whose store failed leaves .owner.lock empty', () async {
    final dir = await tempDir();
    hold('store');
    final session = await Flow(directory: dir).startWorkflow(held, 'store');
    await entered['store']!.future;
    expect(lockOf(dir, session.id), recordOfThisProcess);

    // The effect's result can no longer be written.
    Directory(p.join(sessionDirOf(dir, session.id), documentsDirName))
        .deleteSync(recursive: true);
    gates['store']!.complete();
    await expectLater(session.result, throwsA(isA<StorageException>()));

    expect(lockOf(dir, session.id), isEmpty);
  });

  test(
    'a session of a flow that is stopped leaves .owner.lock empty',
    () async {
      final dir = await tempDir();
      final flow = Flow(directory: dir);
      hold('stopped');
      final session = await flow.startWorkflow(held, 'stopped');
      await entered['stopped']!.future;
      expect(lockOf(dir, session.id), recordOfThisProcess);

      flow.stop();
      gates['stopped']!.complete();
      await expectLater(session.result, throwsA(isA<FlowStoppedException>()));

      expect(lockOf(dir, session.id), isEmpty);
    },
  );

  test('resume records the owner again while the session runs, and clears it '
      'at its end', () async {
    final dir = await tempDir();
    final flow = Flow(directory: dir);
    hold('first');
    final first = await flow.startWorkflow(held, 'first');
    await entered['first']!.future;
    flow.stop();
    gates['first']!.complete();
    await expectLater(first.result, throwsA(isA<FlowStoppedException>()));
    expect(lockOf(dir, first.id), isEmpty);

    hold('first');
    final resumed = await Flow(directory: dir).resumeWorkflow(held, first.id);
    await entered['first']!.future;

    expect(resumed.id, first.id);
    expect(lockOf(dir, first.id), recordOfThisProcess);
    gates['first']!.complete();
    expect(await resumed.result, 'held first');
    expect(lockOf(dir, first.id), isEmpty);
  });
}
