import 'package:nanoflow_process/testing.dart';
import 'package:test/test.dart';

/// 2026-10-03 07:43:34.651 UTC, the start time of the design's example owner.
final DateTime started = DateTime.utc(2026, 10, 3, 7, 43, 34, 651);

/// Whether [future] has completed once the event queue is drained.
Future<bool> completed(Future<void> future) async {
  var done = false;
  future.then((_) => done = true).ignore();
  await pumpEventQueue();
  return done;
}

void main() {
  test('is supported unless made otherwise', () {
    expect(FakeProcesses().supported, isTrue);
    expect(FakeProcesses(supported: false).supported, isFalse);
  });

  group('startOf', () {
    test('gives the start of a started process', () {
      final processes = FakeProcesses()..start(42, started);

      expect(processes.startOf(42), started);
    });

    test('is null for a process never started', () {
      final processes = FakeProcesses()..start(42, started);

      expect(processes.startOf(43), isNull);
    });

    test('is null once the process exited', () {
      final processes = FakeProcesses()
        ..start(42, started)
        ..exit(42);

      expect(processes.startOf(42), isNull);
    });

    test('gives the new start of a pid started again after its exit', () {
      final later = started.add(const Duration(hours: 1));
      final processes = FakeProcesses()
        ..start(42, started)
        ..exit(42)
        ..start(42, later);

      expect(processes.startOf(42), later);
    });
  });

  test('refuses to start a pid that is running', () {
    final processes = FakeProcesses()..start(42, started);

    expect(() => processes.start(42, started), throwsStateError);
    expect(processes.startOf(42), started);
  });

  test('ignores the exit of a pid that is not running', () async {
    final processes = FakeProcesses()
      ..start(42, started)
      ..exit(43);

    expect(processes.startOf(42), started);
    expect(await completed(processes.exitOf(42)), isFalse);
  });

  group('exitOf', () {
    test('completes when the process exits, not before', () async {
      final processes = FakeProcesses()..start(42, started);
      final exited = processes.exitOf(42);

      expect(await completed(exited), isFalse);
      processes.exit(42);
      expect(await completed(exited), isTrue);
    });

    test('completes every wait of the process, and only those', () async {
      final processes = FakeProcesses()
        ..start(42, started)
        ..start(43, started);
      final first = processes.exitOf(42);
      final second = processes.exitOf(42);
      final other = processes.exitOf(43);

      processes.exit(42);
      expect(await completed(first), isTrue);
      expect(await completed(second), isTrue);
      expect(await completed(other), isFalse);
      processes.exit(43);
      expect(await completed(other), isTrue);
    });

    test('completes at once for a process that is not running', () async {
      final processes = FakeProcesses()
        ..start(42, started)
        ..exit(42);

      expect(await completed(processes.exitOf(42)), isTrue);
      expect(await completed(processes.exitOf(43)), isTrue);
    });
  });

  group('close', () {
    test('leaves the pending waits uncompleted, even when the process '
        'exits', () async {
      final processes = FakeProcesses()..start(42, started);
      final exited = processes.exitOf(42);

      await processes.close();
      processes.exit(42);
      expect(await completed(exited), isFalse);
    });

    test('makes later waits never complete', () async {
      final processes = FakeProcesses();
      await processes.close();

      expect(await completed(processes.exitOf(42)), isFalse);
    });
  });

  test('unsupported, knows no start and no exit', () async {
    final processes = FakeProcesses(supported: false)..start(42, started);
    final exited = processes.exitOf(42);

    expect(processes.startOf(42), isNull);
    processes.exit(42);
    expect(await completed(exited), isFalse);
    expect(await completed(processes.exitOf(43)), isFalse);
  });
}
