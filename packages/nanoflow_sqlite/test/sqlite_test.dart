// What the SQLite adapter does of its own; what every adapter does alike is
// in tests/contract.
import 'dart:async';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_process/testing.dart';
import 'package:nanoflow_sqlite/nanoflow_sqlite.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' hide Session;
import 'package:test/test.dart';

/// A database file in a fresh temporary directory, deleted after the test.
String _dbPath() {
  final dir = Directory.systemTemp.createTempSync('nanoflow_sqlite_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  return p.join(dir.path, 'nested', 'app.db');
}

Future<OpenSession> _create(SqliteStore store, {Owner? owner}) =>
    store.createSession(
      workflow: 'review',
      graph: null,
      input: null,
      code: null,
      owner: owner,
    );

/// The changes [reader] gives, collected until the test ends.
List<Change> _feed(SqliteReader reader, {List<Object>? errors}) {
  final changes = <Change>[];
  final subscription = reader.changes().listen(
    changes.add,
    onError: (Object error) => errors?.add(error),
  );
  addTearDown(subscription.cancel);
  return changes;
}

Future<void> _until(String what, bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('waited in vain for $what');
}

void main() {
  test('lives in a database of the app next to its own tables, creating '
      'its directory, the file and the nanoflow tables', () async {
    final path = _dbPath();
    Directory(p.dirname(path)).createSync();
    sqlite3.open(path)
      ..execute('CREATE TABLE ideas (id INTEGER PRIMARY KEY, title TEXT)')
      ..execute("INSERT INTO ideas (title) VALUES ('one')")
      ..close();
    final store = SqliteStore(path);
    addTearDown(store.close);

    await (await _create(store)).release();

    final db = sqlite3.open(path);
    addTearDown(db.close);
    final tables = [
      for (final row in db.select(
        "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
      ))
        row['name'] as String,
    ];
    expect(tables, [
      'ideas',
      'nanoflow_documents',
      'nanoflow_effects',
      'nanoflow_events',
      'nanoflow_logs',
      'nanoflow_meta',
      'nanoflow_owners',
      'nanoflow_sessions',
    ]);
    expect(db.select('SELECT title FROM ideas').single['title'], 'one');
    expect(db.select("SELECT value FROM nanoflow_meta WHERE key = 'schema'"), [
      {'value': '$schemaVersion'},
    ]);
    expect(db.select('PRAGMA journal_mode').single.values.single, 'wal');
  });

  test('refuses tables of a newer version, to write and to read', () async {
    final path = _dbPath();
    final store = SqliteStore(path);
    await (await _create(store)).release();
    store.close();
    sqlite3.open(path)
      ..execute("UPDATE nanoflow_meta SET value = '2' WHERE key = 'schema'")
      ..close();

    await expectLater(
      _create(SqliteStore(path)),
      throwsA(
        isA<SchemaVersionException>().having((e) => e.version, 'version', 2),
      ),
    );
    final errors = <Object>[];
    _feed(SqliteReader(path, processes: FakeProcesses()), errors: errors);
    await _until('the error', () => errors.isNotEmpty);
    expect(errors.first, isA<SchemaVersionException>());
  });

  test('the reader waits for the database and its tables, creating none, '
      'then gives the sessions', () async {
    final path = _dbPath();
    final changes = _feed(
      SqliteReader(
        path,
        pollInterval: const Duration(milliseconds: 10),
        processes: FakeProcesses(),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(File(path).existsSync(), isFalse);
    Directory(p.dirname(path)).createSync();
    sqlite3.open(path)
      ..execute('CREATE TABLE ideas (id INTEGER PRIMARY KEY)')
      ..close();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(changes, isEmpty);

    final store = SqliteStore(path);
    addTearDown(store.close);
    final session = await _create(store);
    await session.release();

    await _until('session-added', () => changes.isNotEmpty);
    expect(changes.first, SessionAdded(session.session));
  });

  test('the reader gives an effect written again as effect-changed, and has '
      'no paths', () async {
    final path = _dbPath();
    final store = SqliteStore(path);
    addTearDown(store.close);
    final session = await _create(store);
    addTearDown(session.release);
    final effect = await session.createEffect(
      name: 'collect',
      key: 'collect#1@e3b0c44298fc1c14',
      after: null,
      place: null,
    );
    final reader = SqliteReader(
      path,
      pollInterval: const Duration(milliseconds: 10),
      processes: FakeProcesses(),
    );
    final changes = _feed(reader);
    await _until('the effect', () => changes.contains(EffectAdded(effect)));

    final outputId = await session.writeDocument(1);
    final done = await session.setEffectOutput(effect, outputId);

    await _until('effect-changed', () => changes.contains(EffectChanged(done)));
    expect(reader.sessionPath(session.session.id), isNull);
    expect(reader.effectPath(effect.id), isNull);
    expect(reader.logPath(effect.id), isNull);
    expect(reader.documentPath(session.session.id, outputId), isNull);
  });

  test('a row that is not its model: an event is log-corrupted with its '
      'number, a session an error, once', () async {
    final path = _dbPath();
    final store = SqliteStore(path);
    addTearDown(store.close);
    final session = await _create(store);
    await session.release();
    final id = session.session.id;
    sqlite3.open(path)
      ..execute(
        'INSERT INTO nanoflow_events (session_id, json) VALUES (?, ?)',
        [id, 'not json'],
      )
      ..execute(
        'INSERT INTO nanoflow_sessions (id, workflow, created, json) '
        "VALUES (?, 'review', '2026-10-03T10:00:00.000Z', '[]')",
        [newId()],
      )
      ..close();
    final errors = <Object>[];

    final changes = _feed(
      SqliteReader(
        path,
        pollInterval: const Duration(milliseconds: 10),
        processes: FakeProcesses(),
      ),
      errors: errors,
    );

    await _until('log-corrupted', () => changes.any((c) => c is LogCorrupted));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(
      changes.whereType<LogCorrupted>().single,
      LogCorrupted(sessionId: id, line: 2, text: 'not json'),
    );
    expect(errors, [isA<FormatException>()]);
    await expectLater(
      SqliteStore(path).openSession(id).then((s) => s!.events()),
      throwsA(
        isA<StoreCorruptedException>()
            .having((e) => e.line, 'line', 2)
            .having((e) => e.path, 'path', '${p.normalize(path)}#$id'),
      ),
    );
  });

  group('an owner another process left', () {
    late String path;
    late String id;

    /// The owner row of the session, as a process that died would leave it.
    void leave(String owner) {
      final db = sqlite3.open(path);
      db
        ..execute(
          'INSERT INTO nanoflow_owners (session_id, json) VALUES (?, ?)',
          [id, owner],
        )
        ..close();
    }

    setUp(() async {
      path = _dbPath();
      final store = SqliteStore(path);
      final session = await _create(store);
      await session.release();
      store.close();
      id = session.session.id;
    });

    test('without a start time keeps the session busy: whether it runs '
        'cannot be told', () async {
      leave('{"pid":42,"started":null}');

      await expectLater(
        SqliteStore(path, processes: FakeProcesses()).openSession(id),
        throwsA(isA<SessionBusyException>()),
      );
    });

    test('that runs keeps the session busy', () async {
      final started = DateTime.utc(2026, 10, 3, 7, 43, 34, 651);
      leave('{"pid":42,"started":"${formatTime(started)}"}');
      final processes = FakeProcesses()..start(42, started);

      await expectLater(
        SqliteStore(path, processes: processes).openSession(id),
        throwsA(isA<SessionBusyException>()),
      );
    });

    test('whose process the OS says is gone gives the session up: the next '
        'owner is written over it', () async {
      leave('{"pid":42,"started":"2026-10-03T07:43:34.000Z"}');
      final processes = FakeProcesses()
        ..start(42, DateTime.utc(2026, 10, 3, 7, 43, 34, 651));
      final store = SqliteStore(path, processes: processes);
      addTearDown(store.close);

      final session = await store.openSession(
        id,
        owner: const Owner(pid: 7, started: null),
      );

      expect(session, isNotNull);
      final db = sqlite3.open(path);
      addTearDown(db.close);
      expect(
        db.select('SELECT json FROM nanoflow_owners').single['json'],
        '{"pid":7,"started":null}',
      );
      await session!.release();
      expect(db.select('SELECT json FROM nanoflow_owners'), isEmpty);
    });
  });
}
