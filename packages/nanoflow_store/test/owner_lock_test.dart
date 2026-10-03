import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

/// The owner in these tests: a process that started at 07:43:34.651.
final _owner = Owner(
  pid: 42,
  started: DateTime.utc(2026, 10, 3, 7, 43, 34, 651),
);

/// What [_owner] is in `.owner.lock`.
const _ownerText = '{"pid":42,"started":"2026-10-03T07:43:34.651Z"}';

/// A record longer than any of [_owner] and the owners below.
const _longerText = '{"pid":123456789,"started":"2026-10-03T07:43:34.651Z"}';

String _lockPath(SessionHandle handle) => p.join(handle.dir, ownerLockFileName);

Future<SessionHandle> _create(FsStore store) => store.createSession(
  workflow: 'review',
  graph: null,
  input: null,
  code: null,
);

/// A process that holds an exclusive lock on [path]: the byte at [offset],
/// or the whole file without one. Completes once it holds it; fails, with
/// what the process printed to stderr, when it ends without saying so.
Future<void> _holdLock(String path, {int? offset}) async {
  final holder = await Process.start(Platform.resolvedExecutable, [
    p.join('test', 'fixtures', 'hold_lock.dart'),
    path,
    if (offset != null) '$offset',
  ]);
  addTearDown(() => holder.kill(ProcessSignal.sigkill));
  final stderrText = holder.stderr.transform(utf8.decoder).join();
  final lines = await holder.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .take(1)
      .toList();
  if (lines.firstOrNull == 'locked') return;
  // Its stdout is closed: the process has ended, and its stderr ends too.
  final why = lines.isEmpty
      ? 'it ended without printing, stderr: ${await stderrText}'
      : 'it printed "${lines.single}"';
  fail('the process that should hold the lock did not report it: $why');
}

void main() {
  group('the owner record', () {
    test('a session created by a store with an owner holds the owner as JSON, '
        'without a newline, while its handle is open', () async {
      final runsDir = p.join(await tempDir(), 'runs');

      final handle = await _create(FsStore(runsDir, owner: _owner));

      expect(read(_lockPath(handle)), _ownerText);
      expect(read(_lockPath(handle)), jsonEncode(_owner.toJson()));
      await handle.release();
    });

    test('is empty once the handle lets the session go', () async {
      final runsDir = p.join(await tempDir(), 'runs');
      final handle = await _create(FsStore(runsDir, owner: _owner));

      await handle.release();

      expect(read(_lockPath(handle)), isEmpty);
    });

    test('is empty while held by a store without an owner', () async {
      final runsDir = p.join(await tempDir(), 'runs');

      final handle = await _create(FsStore(runsDir));

      expect(File(_lockPath(handle)).existsSync(), isTrue);
      expect(read(_lockPath(handle)), isEmpty);
      await handle.release();
    });

    test('is the store\'s owner in a session it opens, and empty once it lets '
        'the session go', () async {
      final runsDir = p.join(await tempDir(), 'runs');
      final created = await _create(FsStore(runsDir));
      await created.release();

      final opened = (await FsStore(
        runsDir,
        owner: _owner,
      ).openSession(created.session.id))!;

      expect(read(_lockPath(opened)), _ownerText);
      await opened.release();
      expect(read(_lockPath(opened)), isEmpty);
    });

    test('is written for an owner whose start time is not known', () async {
      final runsDir = p.join(await tempDir(), 'runs');

      final handle = await _create(
        FsStore(runsDir, owner: const Owner(pid: 42, started: null)),
      );

      expect(read(_lockPath(handle)), '{"pid":42,"started":null}');
      await handle.release();
    });

    test(
      'replaces a longer old record exactly, leaving no tail of it',
      () async {
        final runsDir = p.join(await tempDir(), 'runs');
        final created = await _create(FsStore(runsDir));
        await created.release();
        // What the owner that was killed left.
        File(_lockPath(created)).writeAsStringSync(_longerText);
        const shorter = Owner(pid: 42, started: null);
        const shorterText = '{"pid":42,"started":null}';
        expect(shorterText.length, lessThan(_longerText.length));

        final opened = (await FsStore(
          runsDir,
          owner: shorter,
        ).openSession(created.session.id))!;

        expect(read(_lockPath(opened)), shorterText);
        await opened.release();
      },
    );

    test('is cleared, not left as the old record, by a store without an owner '
        'that opens the session', () async {
      final runsDir = p.join(await tempDir(), 'runs');
      final created = await _create(FsStore(runsDir));
      await created.release();
      File(_lockPath(created)).writeAsStringSync(_longerText);

      final opened = (await FsStore(runsDir).openSession(created.session.id))!;

      expect(read(_lockPath(opened)), isEmpty);
      await opened.release();
    });

    test('is cleared when the session cannot be opened, and the session can '
        'be opened again', () async {
      final runsDir = p.join(await tempDir(), 'runs');
      final created = await _create(FsStore(runsDir));
      await created.release();
      final sessionFile = File(p.join(created.dir, 'session.json'));
      final saved = sessionFile.readAsStringSync();
      sessionFile.deleteSync();
      final store = FsStore(runsDir, owner: _owner);

      await expectLater(
        store.openSession(created.session.id),
        throwsA(isA<FileSystemException>()),
      );

      expect(read(_lockPath(created)), isEmpty);
      sessionFile.writeAsStringSync(saved);
      final opened = (await store.openSession(created.session.id))!;
      expect(read(_lockPath(opened)), _ownerText);
      await opened.release();
    });
  });

  group('the lock', () {
    test('is the byte at ownerLockOffset: a process that holds it makes '
        'openSession busy', () async {
      final runsDir = p.join(await tempDir(), 'runs');
      final created = await _create(FsStore(runsDir, owner: _owner));
      await created.release();
      await _holdLock(_lockPath(created), offset: ownerLockOffset);

      await expectLater(
        FsStore(runsDir, owner: _owner).openSession(created.session.id),
        throwsA(isA<SessionBusyException>()),
      );
      // It does not touch what the other process holds.
      expect(read(_lockPath(created)), isEmpty);
    });

    test('is not the first byte: a process that holds it does not make '
        'openSession busy', () async {
      final runsDir = p.join(await tempDir(), 'runs');
      final created = await _create(FsStore(runsDir, owner: _owner));
      await created.release();
      await _holdLock(_lockPath(created), offset: 0);

      final opened = (await FsStore(
        runsDir,
        owner: _owner,
      ).openSession(created.session.id))!;

      expect(read(_lockPath(opened)), _ownerText);
      await opened.release();
    });

    test('is excluded by the lock of the whole file that an earlier version '
        'takes', () async {
      final runsDir = p.join(await tempDir(), 'runs');
      final created = await _create(FsStore(runsDir, owner: _owner));
      await created.release();
      await _holdLock(_lockPath(created));

      await expectLater(
        FsStore(runsDir, owner: _owner).openSession(created.session.id),
        throwsA(isA<SessionBusyException>()),
      );
    });

    test('keeps another owner out of a session this process owns, and lets '
        'it in once the owner lets go', () async {
      final runsDir = p.join(await tempDir(), 'runs');
      final created = await _create(FsStore(runsDir, owner: _owner));
      final id = created.session.id;

      expect(await ownerCheck(runsDir, id), 'busy');
      // What the owner wrote is there to read. Reading it here, in the process
      // that holds the lock, drops the lock, so it comes after the busy check
      // and release follows.
      expect(read(_lockPath(created)), _ownerText);

      await created.release();
      expect(await ownerCheck(runsDir, id), 'opened');
    });
  });
}
