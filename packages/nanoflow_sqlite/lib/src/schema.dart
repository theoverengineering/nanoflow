// The tables of nanoflow in a database of the app (storage design §6.5). They
// hold what the files of `runs/` hold, the same JSON as text; their names start
// with `nanoflow_`, so that they can live next to the app's own.
//
// Nothing is deleted from them but the row of an owner. So `seq`, the rowid,
// grows in the order of the commits — the writers of SQLite go one at a time —
// and a reader reads all after the last it has seen. The `rev` of an effect is
// `max(rev) + 1` at each write of the effect: a reader learns that way that
// its record was written again.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// The version of the tables this package writes and reads.
const schemaVersion = 1;

const _tables = '''
CREATE TABLE IF NOT EXISTS nanoflow_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS nanoflow_sessions (
  seq INTEGER PRIMARY KEY,
  id TEXT NOT NULL UNIQUE,
  workflow TEXT NOT NULL,
  created TEXT NOT NULL,
  json TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS nanoflow_sessions_workflow
  ON nanoflow_sessions (workflow, created);
CREATE TABLE IF NOT EXISTS nanoflow_events (
  seq INTEGER PRIMARY KEY,
  session_id TEXT NOT NULL,
  json TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS nanoflow_events_session
  ON nanoflow_events (session_id, seq);
CREATE TABLE IF NOT EXISTS nanoflow_effects (
  seq INTEGER PRIMARY KEY,
  id TEXT NOT NULL UNIQUE,
  session_id TEXT NOT NULL,
  rev INTEGER NOT NULL,
  json TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS nanoflow_effects_session
  ON nanoflow_effects (session_id, seq);
CREATE INDEX IF NOT EXISTS nanoflow_effects_rev ON nanoflow_effects (rev);
CREATE TABLE IF NOT EXISTS nanoflow_documents (
  seq INTEGER PRIMARY KEY,
  id TEXT NOT NULL UNIQUE,
  session_id TEXT NOT NULL,
  json TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS nanoflow_logs (
  seq INTEGER PRIMARY KEY,
  effect_id TEXT NOT NULL,
  bytes BLOB NOT NULL
);
CREATE INDEX IF NOT EXISTS nanoflow_logs_effect
  ON nanoflow_logs (effect_id, seq);
CREATE TABLE IF NOT EXISTS nanoflow_owners (
  session_id TEXT PRIMARY KEY,
  json TEXT NOT NULL
);
''';

/// The database has nanoflow tables of a version this package does not
/// know: a newer nanoflow wrote them.
final class SchemaVersionException implements Exception {
  const SchemaVersionException(this.path, this.version);

  /// The database file.
  final String path;

  /// The version of its tables.
  final int version;

  @override
  String toString() =>
      'SchemaVersionException: the nanoflow tables of $path are of version '
      '$version; this nanoflow knows up to $schemaVersion';
}

/// Something a session should have is not in the database.
final class RecordNotFoundException implements Exception {
  const RecordNotFoundException(this.what);

  /// What is missing, and where.
  final String what;

  @override
  String toString() => 'RecordNotFoundException: $what';
}

/// The database at [path] open to write sessions: its directory and the
/// file are created when missing, and so are the tables, in WAL, waiting
/// 5 s for a database another process writes.
///
/// Throws a [SchemaVersionException] when its tables are newer than this
/// package.
Database openForWriting(String path) {
  Directory(p.dirname(path)).createSync(recursive: true);
  final db = sqlite3.open(path);
  try {
    db
      ..execute('PRAGMA busy_timeout = 5000')
      ..execute('PRAGMA journal_mode = WAL');
    inTransaction(db, () {
      db.execute(_tables);
      final version = _version(db);
      if (version == null) {
        db.execute(
          "INSERT INTO nanoflow_meta (key, value) VALUES ('schema', ?)",
          ['$schemaVersion'],
        );
      } else if (version > schemaVersion) {
        throw SchemaVersionException(path, version);
      }
    });
    return db;
  } catch (_) {
    db.close();
    rethrow;
  }
}

/// The database at [path] open to read sessions, or `null` while there is
/// none, or it has no nanoflow tables yet. Creates nothing.
///
/// Throws a [SchemaVersionException] when its tables are newer than this
/// package.
Database? openForReading(String path) {
  if (!File(path).existsSync()) return null;
  final Database db;
  try {
    db = sqlite3.open(path, mode: OpenMode.readWrite);
  } on SqliteException {
    return null;
  }
  try {
    db.execute('PRAGMA busy_timeout = 5000');
    final version = _version(db);
    if (version == null) {
      db.close();
      return null;
    }
    if (version > schemaVersion) throw SchemaVersionException(path, version);
    return db;
  } catch (_) {
    db.close();
    rethrow;
  }
}

/// Runs [body] in one transaction of [db] that takes the write lock at once:
/// commits what it wrote, or rolls it back when it throws.
T inTransaction<T>(Database db, T Function() body) {
  db.execute('BEGIN IMMEDIATE');
  try {
    final result = body();
    db.execute('COMMIT');
    return result;
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
}

/// Runs [body] in one transaction of [db] that reads: it sees the database
/// as it was at its first read, whatever others commit meanwhile.
T inSnapshot<T>(Database db, T Function() body) {
  db.execute('BEGIN');
  try {
    return body();
  } finally {
    db.execute('COMMIT');
  }
}

/// The version of the nanoflow tables of [db]; `null` when it has none.
int? _version(Database db) {
  final meta = db.select(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND "
    "name = 'nanoflow_meta'",
  );
  if (meta.isEmpty) return null;
  final rows = db.select(
    "SELECT value FROM nanoflow_meta WHERE key = 'schema'",
  );
  return rows.isEmpty ? null : int.parse(rows.single['value'] as String);
}
