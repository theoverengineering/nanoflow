@TestOn('mac-os')
library;

import 'dart:async';
import 'dart:io';

import 'package:nanoflow_process/nanoflow_process.dart';
import 'package:nanoflow_process/src/mac_processes.dart' show timeOfTimeval;
import 'package:test/test.dart';

/// How long a process may take to be told gone after it died.
const exitWait = Duration(seconds: 5);

/// Expects [future] to be still pending after [wait].
Future<void> expectPending(
  Future<void> future, [
  Duration wait = const Duration(milliseconds: 200),
]) => expectLater(future.timeout(wait), throwsA(isA<TimeoutException>()));

/// Starts `sleep [seconds]`, killed when the test ends.
Future<Process> sleeping([String seconds = '30']) async {
  final process = await Process.start('sleep', [seconds]);
  addTearDown(() {
    process.kill(ProcessSignal.sigkill);
    return process.exitCode;
  });
  return process;
}

/// The pid of a process that has exited and was reaped.
Future<int> gonePid() async => (await Process.run('true', [])).pid;

void main() {
  late MacProcesses processes;

  setUp(() {
    processes = MacProcesses();
    addTearDown(processes.close);
  });

  test('is what the platform gives, and is supported', () {
    expect(Processes.forPlatform(), isA<MacProcesses>());
    expect(processes.supported, isTrue);
  });

  group('startOf', () {
    test('gives this process a start in UTC milliseconds, not after now and '
        'the same on every call', () {
      final start = processes.startOf(pid);

      expect(start, isNotNull);
      expect(start!.isUtc, isTrue);
      expect(start.microsecond, 0);
      expect(start.isAfter(DateTime.now()), isFalse);
      expect(processes.startOf(pid), start);
    });

    test('gives a child the start it just had, not before this process '
        'started', () async {
      final child = await sleeping();

      final start = processes.startOf(child.pid)!;

      expect(
        start.difference(DateTime.now()).abs(),
        lessThan(const Duration(seconds: 5)),
      );
      expect(start.isBefore(processes.startOf(pid)!), isFalse);
    });

    test('is null for a process that is gone', () async {
      expect(processes.startOf(await gonePid()), isNull);
    });

    test('drops the microseconds of the OS time, never rounding them up', () {
      expect(
        timeOfTimeval(1791013414, 651999),
        DateTime.utc(2026, 10, 3, 7, 43, 34, 651),
      );
    });
  });

  group('exitOf', () {
    test('completes once the process is killed, not before', () async {
      final child = await sleeping();
      final exited = processes.exitOf(child.pid);

      await expectPending(exited);
      child.kill(ProcessSignal.sigkill);
      await exited.timeout(exitWait);
    });

    test('completes when the process exits by itself', () async {
      final child = await sleeping('0.2');

      await processes.exitOf(child.pid).timeout(exitWait);
    });

    test('completes at once for a process that is gone', () async {
      var done = false;
      processes.exitOf(await gonePid()).then((_) => done = true).ignore();

      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
    });

    test('completes every wait when its process dies', () async {
      final child = await sleeping();
      final other = await sleeping();
      final first = processes.exitOf(child.pid);
      final second = processes.exitOf(child.pid);
      final otherExited = processes.exitOf(other.pid);

      child.kill(ProcessSignal.sigkill);
      await first.timeout(exitWait);
      await second.timeout(exitWait);
      await expectPending(otherExited);
      other.kill(ProcessSignal.sigkill);
      await otherExited.timeout(exitWait);
    });
  });

  group('close', () {
    test('stops the watcher: a pending wait never completes, even when its '
        'process dies', () async {
      final child = await sleeping();
      final exited = processes.exitOf(child.pid);
      // The watcher is waiting in the OS by now.
      await expectPending(exited);

      await processes.close().timeout(exitWait);
      child.kill(ProcessSignal.sigkill);
      await child.exitCode;
      await expectPending(exited, const Duration(milliseconds: 500));
    });

    test('makes later waits never complete, even for a process that is '
        'gone', () async {
      await processes.close();

      await expectPending(processes.exitOf(await gonePid()));
    });

    test('can be called again, also while closing', () async {
      final child = await sleeping();
      processes.exitOf(child.pid).ignore();

      await Future.wait([processes.close(), processes.close()])
          .timeout(exitWait);
      await processes.close();
    });

    test('closes an adapter that never watched', () async {
      processes.startOf(pid);

      await processes.close();
      await processes.close();
    });

    test('lets the program end with a wait pending', () async {
      final watcher = await Process.start(Platform.resolvedExecutable, [
        'run',
        'test/fixtures/watch_and_close.dart',
      ]);
      addTearDown(() => watcher.kill(ProcessSignal.sigkill));
      final stderr = watcher.stderr
          .transform(const SystemEncoding().decoder)
          .join();
      watcher.stdout.drain<void>().ignore();

      expect(
        await watcher.exitCode.timeout(const Duration(seconds: 30)),
        0,
        reason: await stderr,
      );
    });
  });
}
