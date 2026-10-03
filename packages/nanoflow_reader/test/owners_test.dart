// The owner of a session whose journal goes on, as the feed tells it
// (design §5): with a fake OS port, whose processes the tests start and end.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_process/nanoflow_process.dart';
import 'package:nanoflow_process/testing.dart';
import 'package:nanoflow_reader/src/fs_reader.dart' show readerOwning;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

/// When the process of [owner] started.
final DateTime started = DateTime.utc(2026, 10, 3, 7, 43, 34, 651);

/// The owner in these tests: the process 4242.
final Owner owner = Owner(pid: 4242, started: started);

/// The owner that resumes the session of [owner].
final Owner resumer = Owner(pid: 4343, started: at(30));

/// The first event of every session here.
final SessionStarted begun = SessionStarted(time: at(0), code: null);

void main() {
  late String runsDir;
  late FakeProcesses processes;

  setUp(() async {
    runsDir = await newRunsDir();
    processes = FakeProcesses();
  });

  /// Writes a session whose journal has [events], with [lock] in its
  /// `.owner.lock`, or no such file; gives it and its directory.
  ({Session session, String dir}) writeOwned(
    String? lock, {
    List<Event>? events,
    DateTime? createdAt,
  }) {
    final session = newSession();
    final dir = writeSession(
      runsDir,
      session,
      events: events ?? [begun],
      createdAt: createdAt,
    );
    if (lock != null) writeLock(dir, lock);
    return (session: session, dir: dir);
  }

  OwnerChanged changed(Session session, Owner? owner, bool? alive) =>
      OwnerChanged(sessionId: session.id, owner: owner, alive: alive);

  group('on the first read', () {
    test('comes after the other changes of a session whose journal goes on, '
        'with no owner and not alive when .owner.lock is empty or '
        'missing', () async {
      final events = [begun, StepStarted(time: at(1), stepId: newId())];
      final released = writeOwned('', events: events, createdAt: at(60));
      final document = Document(
        id: newId(),
        sessionId: released.session.id,
        value: 1,
      );
      writeDocument(released.dir, document);
      // Written by a version without owners.
      final old = writeOwned(null, createdAt: at(0));

      final feed = Feed(runsDir, processes: processes);
      await feed.settle();

      expect(feed.changes, [
        SessionAdded(released.session),
        for (final event in events)
          EventAdded(sessionId: released.session.id, event: event),
        DocumentAdded(sessionId: released.session.id, documentId: document.id),
        changed(released.session, null, false),
        SessionAdded(old.session),
        EventAdded(sessionId: old.session.id, event: begun),
        changed(old.session, null, false),
      ]);
      expect(feed.errors, isEmpty);
    });

    test('is alive when the process with the pid of the owner runs and '
        'started when the owner says', () async {
      processes.start(owner.pid, started);
      final session = writeOwned(record(owner)).session;

      final feed = Feed(runsDir, processes: processes);
      await feed.settle();

      expect(feed.changes.last, changed(session, owner, true));
    });

    test('is not alive when the pid is another process now, or no process '
        'at all', () async {
      processes.start(owner.pid, started.add(const Duration(seconds: 1)));
      final reused = writeOwned(record(owner), createdAt: at(60)).session;
      final gone = Owner(pid: 4343, started: started);
      final none = writeOwned(record(gone), createdAt: at(0)).session;

      final feed = Feed(runsDir, processes: processes);
      await feed.settle();

      expect(feed.changes.whereType<OwnerChanged>(), [
        changed(reused, owner, false),
        changed(none, gone, false),
      ]);
    });

    test('is unknown when the owner has no start', () async {
      processes.start(owner.pid, started);
      final unknown = Owner(pid: owner.pid, started: null);
      final session = writeOwned(record(unknown)).session;

      final feed = Feed(runsDir, processes: processes);
      await feed.settle();

      expect(feed.changes.last, changed(session, unknown, null));
    });

    test('is unknown when the OS port cannot tell', () async {
      final unsupported = FakeProcesses(supported: false)
        ..start(owner.pid, started);
      final session = writeOwned(record(owner)).session;

      final feed = Feed(runsDir, processes: unsupported);
      await feed.settle();

      expect(feed.changes.last, changed(session, owner, null));
    });

    test('is not given for a session whose journal has ended', () async {
      processes.start(owner.pid, started);
      final finished = SessionFinished(time: at(5), outputId: null);
      final failed = SessionFailed(time: at(5), error: 'boom', stack: '');
      writeOwned(record(owner), events: [begun, finished], createdAt: at(60));
      writeOwned(record(owner), events: [begun, failed], createdAt: at(0));

      final feed = Feed(runsDir, processes: processes);
      await feed.settle();
      processes.exit(owner.pid);
      await feed.settle();
      await feed.settle();

      expect(feed.changes.whereType<OwnerChanged>(), isEmpty);
    });
  });

  group('later', () {
    test('turns not alive, with the same owner, as soon as its process '
        'exits', () async {
      processes.start(owner.pid, started);
      final session = writeOwned(record(owner)).session;
      // Nothing on disk changes: only the exit can make the reader look.
      final feed = Feed(
        runsDir,
        processes: processes,
        pollInterval: const Duration(hours: 1),
      );
      await feed.next<OwnerChanged>();
      final mark = feed.changes.length;

      processes.exit(owner.pid);
      await feed.next<OwnerChanged>((change) => change.alive == false);
      await feed.settle();
      await feed.settle();

      expect(feed.since(mark), [changed(session, owner, false)]);
    });

    test('turns no owner when .owner.lock is emptied', () async {
      processes.start(owner.pid, started);
      final (:session, :dir) = writeOwned(record(owner));
      final feed = Feed(runsDir, processes: processes);
      await feed.settle();
      final mark = feed.changes.length;

      writeLock(dir, '');
      await feed.settle();
      await feed.settle();

      expect(feed.since(mark), [changed(session, null, false)]);
    });

    test('gives the new owner of a session resumed after its owner '
        'exited', () async {
      processes.start(owner.pid, started);
      final (:session, :dir) = writeOwned(record(owner));
      final feed = Feed(runsDir, processes: processes);
      await feed.settle();
      final mark = feed.changes.length;
      processes.exit(owner.pid);
      await feed.next<OwnerChanged>((change) => change.alive == false);

      processes.start(resumer.pid, resumer.started!);
      writeLock(dir, record(resumer));
      final resumed = SessionResumed(time: at(30), code: null, graphId: null);
      append(dir, line(resumed));
      await feed.settle();
      await feed.settle();

      expect(feed.since(mark), [
        changed(session, owner, false),
        EventAdded(sessionId: session.id, event: resumed),
        changed(session, resumer, true),
      ]);
    });

    test('gives session-finished and never not alive when the session ends, '
        'its owner lets it go and its process exits', () async {
      processes.start(owner.pid, started);
      final (:session, :dir) = writeOwned(record(owner));
      final feed = Feed(runsDir, processes: processes);
      await feed.settle();
      final mark = feed.changes.length;

      // The order of the library and the store: the last event, the lock let
      // go, then the exit.
      final finished = SessionFinished(time: at(5), outputId: null);
      append(dir, line(finished));
      writeLock(dir, '');
      processes.exit(owner.pid);
      await feed.settle();
      await feed.settle();
      // The session is over: whatever its .owner.lock says now is not told.
      writeLock(dir, record(resumer));
      await feed.settle();
      await feed.settle();

      expect(feed.since(mark), [
        EventAdded(sessionId: session.id, event: finished),
      ]);
    });

    test('gives session-finished and no owner-changed when the owner ends '
        'the session, lets it go and exits as the reader first looks at '
        'it', () async {
      final port = _Spy(processes..start(owner.pid, started));
      final (:session, :dir) = writeOwned(record(owner));
      final finished = SessionFinished(time: at(5), outputId: null);
      port.beforeStartOf = () {
        append(dir, line(finished));
        writeLock(dir, '');
        processes.exit(owner.pid);
      };

      final feed = Feed(runsDir, processes: port);
      await feed.settle();
      await feed.settle();

      expect(port.calls, contains('startOf ${owner.pid}'));
      expect(feed.changes, [
        SessionAdded(session),
        EventAdded(sessionId: session.id, event: begun),
        EventAdded(sessionId: session.id, event: finished),
      ]);
    });

    test('tells nothing when the owner before a resume exits after the new '
        'owner was told', () async {
      processes
        ..start(owner.pid, started)
        ..start(resumer.pid, resumer.started!);
      final (:session, :dir) = writeOwned(record(owner));
      final feed = Feed(runsDir, processes: processes);
      await feed.settle();
      final mark = feed.changes.length;

      writeLock(dir, record(resumer));
      await feed.settle();
      await feed.settle();
      expect(feed.since(mark), [changed(session, resumer, true)]);

      processes.exit(owner.pid);
      await feed.settle();
      await feed.settle();

      expect(feed.since(mark), [changed(session, resumer, true)]);
    });

    test('keeps what it told, without an error, while .owner.lock does not '
        'hold an owner, and tells the owner once it does', () async {
      processes
        ..start(owner.pid, started)
        ..start(resumer.pid, resumer.started!);
      final (:session, :dir) = writeOwned('{"pid": 4');
      final feed = Feed(runsDir, processes: processes);
      await feed.settle();
      await feed.settle();
      expect(feed.changes.whereType<OwnerChanged>(), isEmpty);

      writeLock(dir, record(owner));
      await feed.next<OwnerChanged>();
      final mark = feed.changes.length;
      // Another owner being written, and records that are not owners.
      for (final text in ['{"pid": 4', '[]', '{"pid":"4343","started":null}']) {
        writeLock(dir, text);
        await feed.settle();
        await feed.settle();
      }
      expect(feed.since(mark), isEmpty);

      writeLock(dir, record(resumer));
      await feed.settle();

      expect(feed.since(mark), [changed(session, resumer, true)]);
      expect(feed.errors, isEmpty);
    });

    test('turns unknown when watching the exit fails', () async {
      final port = _Spy(processes..start(owner.pid, started));
      final session = writeOwned(record(owner)).session;
      final feed = Feed(runsDir, processes: port);
      await feed.settle();
      final mark = feed.changes.length;

      port.breakWatching();
      await feed.next<OwnerChanged>((change) => change.alive == null);
      await feed.settle();
      await feed.settle();

      expect(feed.since(mark), [changed(session, owner, null)]);
      expect(feed.errors, isEmpty);
    });

    test('gives a .owner.lock it cannot read as an error, once, and the owner '
        'once it can', () async {
      processes.start(owner.pid, started);
      final (:session, :dir) = writeOwned(record(owner));
      final lock = p.join(dir, ownerLockFileName);
      Process.runSync('chmod', ['000', lock]);

      final feed = Feed(runsDir, processes: processes);
      await feed.settle();
      await feed.settle();
      expect(feed.changes.whereType<OwnerChanged>(), isEmpty);
      expect(feed.errors, [
        isA<FileSystemException>().having((e) => e.path, 'path', lock),
      ]);

      Process.runSync('chmod', ['644', lock]);
      await feed.settle();
      expect(feed.changes.last, changed(session, owner, true));
      expect(feed.errors, hasLength(1));
    }, skip: skipAsRoot);
  });

  group('the OS port', () {
    test('is asked for the exit of the owner before its start, so an exit '
        'in between is not missed', () async {
      final port = _Spy(processes..start(owner.pid, started));
      writeOwned(record(owner));

      await Feed(runsDir, processes: port).settle();

      expect(port.calls, ['exitOf ${owner.pid}', 'startOf ${owner.pid}']);
    });

    test('of its own is closed when the feed is cancelled, and one it was '
        'given is not', () async {
      final own = _Spy(FakeProcesses());
      final given = _Spy(FakeProcesses());
      final ownFeed = Feed.of(readerOwning(own, runsDir: runsDir));
      final givenFeed = Feed(runsDir, processes: given);
      await ownFeed.settle();
      await givenFeed.settle();
      expect(own.closes, 0);

      await ownFeed.cancel();
      await givenFeed.cancel();

      expect(own.closes, 1);
      expect(given.closes, 0);
    });

    test('of its own has closed by the time the cancel of the feed '
        'completes: an app waits for that before it quits', () async {
      final closing = Completer<void>();
      final own = _Spy(FakeProcesses())..closing = closing.future;
      final feed = Feed.of(readerOwning(own, runsDir: runsDir));
      // Lets the feed's own cancel at the end of the test complete.
      addTearDown(() {
        if (!closing.isCompleted) closing.complete();
      });
      await feed.settle();

      var cancelled = false;
      final cancel = feed.cancel().then((_) => cancelled = true);
      // The cancel waits for a scan under way before it closes the port.
      while (own.closes == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await pumpEventQueue();
      expect(cancelled, isFalse);

      closing.complete();
      await cancel;
    });

    test('is not asked again when the owner exits after the feed is '
        'cancelled: no scan runs to tell it', () async {
      final port = _Spy(processes..start(owner.pid, started));
      final dir = writeOwned(record(owner)).dir;
      final feed = Feed(runsDir, processes: port);
      await feed.next<OwnerChanged>();
      await feed.cancel();
      final calls = [...port.calls];

      // A scan would ask about the new owner.
      processes.start(resumer.pid, resumer.started!);
      writeLock(dir, record(resumer));
      processes.exit(owner.pid);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(port.calls, calls);
    });
  });
}

/// The JSON of [owner] in `.owner.lock`, as the store writes it.
String record(Owner owner) => jsonEncode(owner.toJson());

/// Writes [text] into the `.owner.lock` of the session in [sessionDir] as
/// the store does: from its start, then cut at its length, so a reader never
/// sees an empty file in between.
void writeLock(String sessionDir, String text) {
  final file = File(p.join(sessionDir, ownerLockFileName))
      .openSync(mode: FileMode.append);
  try {
    final bytes = utf8.encode(text);
    file
      ..setPositionSync(0)
      ..writeFromSync(bytes)
      ..truncateSync(bytes.length);
  } finally {
    file.closeSync();
  }
}

/// The processes of [fake], with the calls the reader makes recorded, and
/// the exit waits it gives failing on [breakWatching].
final class _Spy implements Processes {
  _Spy(this.fake);

  final FakeProcesses fake;

  /// `exitOf <pid>` and `startOf <pid>`, in the order they were made.
  final List<String> calls = [];

  /// How many times [close] was called.
  int closes = 0;

  /// What [close] waits for before it completes, besides the fake.
  Future<void>? closing;

  /// Runs once, when [startOf] is next called, before it answers.
  void Function()? beforeStartOf;

  final List<Completer<void>> _waits = [];

  @override
  bool get supported => fake.supported;

  @override
  DateTime? startOf(int pid) {
    calls.add('startOf $pid');
    final before = beforeStartOf;
    beforeStartOf = null;
    before?.call();
    return fake.startOf(pid);
  }

  @override
  Future<void> exitOf(int pid) {
    calls.add('exitOf $pid');
    final wait = Completer<void>();
    _waits.add(wait);
    unawaited(
      fake.exitOf(pid).then((_) {
        if (!wait.isCompleted) wait.complete();
      }),
    );
    return wait.future;
  }

  /// Fails the exit waits given so far, as the macOS adapter does when its
  /// watcher stops.
  void breakWatching() {
    for (final wait in _waits) {
      if (!wait.isCompleted) {
        wait.completeError(const OSError('Stopped watching for exits'));
      }
    }
  }

  @override
  Future<void> close() async {
    closes++;
    await fake.close();
    await closing;
  }
}
