@TestOn('mac-os')
library;

import 'dart:async';
import 'dart:convert';
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

/// The program of the fixture test/fixtures/[name].dart, compiled as an
/// app's code is: such a program ends sooner than under `dart run`, soon
/// enough to show what lets it end too early.
Future<String> compiled(String name) async {
  final dir = await Directory.systemTemp.createTemp('nanoflow_process_test');
  addTearDown(() => dir.delete(recursive: true));
  final program = '${dir.path}/$name';
  final result = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'exe',
    'test/fixtures/$name.dart',
    '-o',
    program,
  ]);
  if (result.exitCode != 0) {
    fail('cannot compile $name: ${result.stdout}${result.stderr}');
  }
  return program;
}

/// Starts [program] with [arguments], killed when the test ends.
Future<Process> start(String program, List<String> arguments) async {
  final process = await Process.start(program, arguments);
  addTearDown(() => process.kill(ProcessSignal.sigkill));
  return process;
}

/// All that [stream] of a process gives, as text.
Future<String> textOf(Stream<List<int>> stream) =>
    stream.transform(utf8.decoder).join();

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

    test('completes as the process dies, not when the watcher next looks: '
        'it waits on the OS for half a second at a time', () async {
      // Were the exit seen only at the end of each wait, every kill would be
      // told up to half a second late, and five of them not all early.
      for (var i = 0; i < 5; i++) {
        final child = await sleeping();
        final exited = processes.exitOf(child.pid);
        await expectPending(exited, const Duration(milliseconds: 100));

        final told = Stopwatch()..start();
        child.kill(ProcessSignal.sigkill);
        await exited.timeout(exitWait);
        expect(told.elapsed, lessThan(const Duration(milliseconds: 250)));
      }
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

    test('completes, and then lets the program end, with a wait '
        'pending', () async {
      final child = await sleeping();
      final program = await compiled('watch_and_close');

      // A program that ended during the close would end without a word, and
      // mostly does when the close does not hold it: it is run a few times.
      for (var i = 0; i < 3; i++) {
        final run = await start(program, ['${child.pid}']);
        final stdout = textOf(run.stdout);
        final stderr = textOf(run.stderr);
        expect(await run.exitCode.timeout(exitWait), 0, reason: await stderr);
        expect(await stdout, 'closed\n');
      }
    });

    test('is not needed for the program to end once nothing waits, though a '
        'pending wait keeps it running', () async {
      final child = await sleeping();
      final run = await start(await compiled('watch_and_forget'), [
        '${child.pid}',
      ]);
      final stderr = textOf(run.stderr);
      final lines = StreamIterator(
        run.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );

      if (!await lines.moveNext()) fail('it ended at once: ${await stderr}');
      expect(lines.current, 'watching');
      await expectPending(run.exitCode, const Duration(milliseconds: 500));

      child.kill(ProcessSignal.sigkill);
      // The watcher waits on the kqueue still, and the program ends anyway.
      expect(await run.exitCode.timeout(exitWait), 0, reason: await stderr);
      expect(await lines.moveNext(), isTrue);
      expect(lines.current, 'gone');
    });
  });
}
