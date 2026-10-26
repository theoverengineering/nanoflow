import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_process/nanoflow_process.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' hide Session;

import 'schema.dart';

/// The sessions in an SQLite database of the app, as the process that runs
/// them keeps them (storage design §6.6).
///
/// Every write is a transaction of its own: a session is created whole, in
/// one; what it writes later — an event, a document, an effect — goes one by
/// one, as files go in `runs/`. Several processes may write the database at
/// once: it is in WAL, and a writer waits 5 s for another.
///
/// The owner of a session is a row of `nanoflow_owners`, not a lock: a
/// process that dies leaves it, and the next one to open the session takes
/// it once the OS says that process is gone.
final class SqliteStore implements SessionStore {
  /// The store of the database [path]: its directory, the file and the
  /// tables are created when missing, at the first write. [processes] tells
  /// whether the owner of a session runs; by default the adapter of this OS.
  SqliteStore(String path, {this._processes, this._clock = systemClock})
    : path = p.normalize(p.absolute(path));

  /// The database file.
  final String path;

  final Processes? _processes;
  final Clock _clock;

  late final Database _db = openForWriting(path);

  late final Processes _os = _processes ?? Processes.forPlatform();

  /// Lets the database go. The sessions this store gave must not be written
  /// any more.
  void close() => _db.close();

  /// Creates a session of the workflow [workflow]: in one transaction, the
  /// session with [graph], the input document when [input] is given,
  /// `session-started` with [code] at the time it is created, and [owner] as
  /// its owner; `null` records none, and then nothing but this isolate keeps
  /// other processes off the session.
  ///
  /// The id is [id] when given: an [ArgumentError] when it is not an id
  /// ([isId]), and a [SessionExistsException] when the database has a
  /// session with it.
  @override
  Future<SqliteSession> createSession({
    required String workflow,
    required Map<String, Object?>? graph,
    required ({Object? value})? input,
    required String? code,
    String? id,
    Owner? owner,
  }) async {
    if (id != null && !isId(id)) {
      throw ArgumentError.value(id, 'id', 'not an id');
    }
    final sessionId = id ?? newId();
    final createdAt = _clock();
    final session = inTransaction(_db, () {
      if (_hasSession(sessionId)) throw SessionExistsException(sessionId);
      final inputId = input == null
          ? null
          : _insertDocument(_db, sessionId, input.value);
      final session = Session(
        id: sessionId,
        workflow: workflow,
        graph: graph,
        inputId: inputId,
      );
      _db.execute(
        'INSERT INTO nanoflow_sessions (id, workflow, created, json) '
        'VALUES (?, ?, ?, ?)',
        [sessionId, workflow, formatTime(createdAt), _json(session.toJson())],
      );
      _insertEvent(_db, sessionId, SessionStarted(time: createdAt, code: code));
      if (owner != null) _setOwner(sessionId, owner);
      return session;
    });
    _hold(sessionId);
    return SqliteSession._(this, session);
  }

  /// The session [sessionId], or `null` when the database has none.
  ///
  /// In one transaction, looks at its owner: none, or one whose process the
  /// OS says is gone, and the session is this process's, with [owner] as
  /// its owner (`null` records none). Throws a [SessionBusyException],
  /// having changed nothing, when the owner runs, or whether it runs cannot
  /// be told — it has no start time, or the OS has no adapter —, or when
  /// this isolate holds the session already.
  @override
  Future<SqliteSession?> openSession(String sessionId, {Owner? owner}) async {
    if (_held.contains(_key(sessionId))) {
      throw SessionBusyException(sessionId);
    }
    final session = inTransaction(_db, () {
      final rows = _db.select(
        'SELECT json FROM nanoflow_sessions WHERE id = ?',
        [sessionId],
      );
      if (rows.isEmpty) return null;
      final session = Session.fromJson(_object(rows.single['json'], 'session'));
      final held = _db.select(
        'SELECT json FROM nanoflow_owners WHERE session_id = ?',
        [sessionId],
      );
      if (held.isNotEmpty && !_gone(_ownerOf(held.single['json']))) {
        throw SessionBusyException(sessionId);
      }
      if (owner == null) {
        _db.execute('DELETE FROM nanoflow_owners WHERE session_id = ?', [
          sessionId,
        ]);
      } else {
        _setOwner(sessionId, owner);
      }
      return session;
    });
    if (session == null) return null;
    _hold(sessionId);
    return SqliteSession._(this, session);
  }

  /// Ids of the sessions of [workflow] whose journal has no
  /// `session-finished` or `session-failed`, newest first: by the time of
  /// their `session-started`, the time they were created. Owns none of them.
  @override
  Future<List<String>> unfinishedSessions(String workflow) async => [
    for (final row in _db.select(
      '''
      SELECT id FROM nanoflow_sessions AS s
      WHERE workflow = ? AND NOT EXISTS (
        SELECT 1 FROM nanoflow_events AS e
        WHERE e.session_id = s.id AND CASE WHEN json_valid(e.json)
          THEN json_extract(e.json, '\$.event') END
          IN ('session-finished', 'session-failed')
      )
      ORDER BY created DESC, seq DESC
      ''',
      [workflow],
    ))
      row['id'] as String,
  ];

  bool _hasSession(String sessionId) => _db.select(
    'SELECT 1 FROM nanoflow_sessions WHERE id = ?',
    [sessionId],
  ).isNotEmpty;

  void _setOwner(String sessionId, Owner owner) => _db.execute(
    'INSERT INTO nanoflow_owners (session_id, json) VALUES (?, ?) '
    'ON CONFLICT (session_id) DO UPDATE SET json = excluded.json',
    [sessionId, _json(owner.toJson())],
  );

  /// Whether the OS says the process of [owner] is gone: there is no process
  /// of its pid, or one that started at another time. `false` when that
  /// cannot be told.
  bool _gone(Owner? owner) {
    if (owner == null) return true;
    final started = owner.started;
    if (started == null || !_os.supported) return false;
    return Owner(pid: owner.pid, started: _os.startOf(owner.pid)) != owner;
  }

  String _key(String sessionId) => '$path#$sessionId';

  void _hold(String sessionId) => _held.add(_key(sessionId));

  void _letGo(String sessionId) => _held.remove(_key(sessionId));
}

/// The sessions this isolate holds, by `<database>#<id>`.
final _held = <String>{};

/// One session in the database that this process owns: what it writes, and
/// what it reads back to continue it after a crash.
final class SqliteSession implements OpenSession {
  SqliteSession._(this._store, this.session);

  final SqliteStore _store;

  @override
  final Session session;

  /// Whether [release] was called.
  bool _released = false;

  Database get _db => _store._db;

  /// Where the session is, for errors: `<database>#<id>`.
  String get _where => '${_store.path}#${session.id}';

  /// The events of the session, in the order they were written. Throws a
  /// [StoreCorruptedException] for one that is not a JSON object.
  @override
  Future<List<Event>> events() async {
    final rows = _db.select(
      'SELECT json FROM nanoflow_events WHERE session_id = ? ORDER BY seq',
      [session.id],
    );
    return [
      for (final (i, row) in rows.indexed)
        if (_decode(row['json']) case final Map<String, Object?> json)
          Event.fromJson(json)
        else
          throw StoreCorruptedException(path: _where, line: i + 1),
    ];
  }

  @override
  Future<List<Effect>> effects() async => [
    for (final row in _db.select(
      'SELECT json FROM nanoflow_effects WHERE session_id = ? ORDER BY seq',
      [session.id],
    ))
      Effect.fromJson(_object(row['json'], 'effect')),
  ];

  @override
  Future<Object?> documentValue(String documentId) async {
    final rows = _db.select(
      'SELECT json FROM nanoflow_documents WHERE id = ? AND session_id = ?',
      [documentId, session.id],
    );
    if (rows.isEmpty) {
      throw RecordNotFoundException('no document $documentId in $_where');
    }
    return Document.fromJson(_object(rows.single['json'], 'document')).value;
  }

  @override
  Future<Effect> createEffect({
    required String name,
    required String key,
    required String? after,
    required String? place,
  }) async {
    final effect = Effect(
      id: newId(),
      sessionId: session.id,
      name: name,
      key: key,
      after: after,
      place: place,
      outputId: null,
      log: logFileName,
    );
    inTransaction(_db, () {
      _checkSession();
      _db.execute(
        'INSERT INTO nanoflow_effects (id, session_id, rev, json) VALUES '
        '(?, ?, (SELECT coalesce(max(rev), 0) + 1 FROM nanoflow_effects), ?)',
        [effect.id, session.id, _json(effect.toJson())],
      );
    });
    return effect;
  }

  /// Appends [event] to the session's journal, at once: events given side by
  /// side go in the order given.
  @override
  Future<void> appendEvent(KnownEvent event) async => inTransaction(_db, () {
    _checkSession();
    _insertEvent(_db, session.id, event);
  });

  @override
  Future<String> writeDocument(Object? value) async => inTransaction(_db, () {
    _checkSession();
    return _insertDocument(_db, session.id, value);
  });

  @override
  Future<Effect> setEffectOutput(Effect effect, String outputId) async =>
      _rewrite(effect.withOutput(outputId));

  @override
  Future<Effect> setEffectAfter(Effect effect, String? after) async =>
      _rewrite(effect.withAfter(after));

  /// Opens the log of the effect [effectId]; an effect that runs again adds
  /// to the log it has. Throws an [ArgumentError] for an effect the session
  /// does not have.
  @override
  SqliteEffectLog openLog(String effectId) {
    final found = _db.select(
      'SELECT 1 FROM nanoflow_effects WHERE id = ? AND session_id = ?',
      [effectId, session.id],
    );
    if (found.isEmpty) {
      throw ArgumentError.value(
        effectId,
        'effectId',
        'no such effect in session ${session.id}',
      );
    }
    return SqliteEffectLog._(_db, effectId);
  }

  /// Gives the session up: removes its owner, and this isolate no longer
  /// holds it. Reading through it still works; writing must not be done any
  /// more.
  @override
  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      inTransaction(_db, () {
        _db.execute('DELETE FROM nanoflow_owners WHERE session_id = ?', [
          session.id,
        ]);
      });
    } finally {
      _store._letGo(session.id);
    }
  }

  /// Writes [effect] over its record; gives it.
  Effect _rewrite(Effect effect) {
    inTransaction(_db, () {
      _db.execute(
        'UPDATE nanoflow_effects SET json = ?, '
        'rev = (SELECT max(rev) + 1 FROM nanoflow_effects) '
        'WHERE id = ? AND session_id = ?',
        [_json(effect.toJson()), effect.id, session.id],
      );
      if (_db.updatedRows == 0) {
        throw RecordNotFoundException('no effect ${effect.id} in $_where');
      }
    });
    return effect;
  }

  /// Throws a [RecordNotFoundException] when the session is not in the
  /// database any more: it was removed while this process ran it.
  void _checkSession() {
    if (!_store._hasSession(session.id)) {
      throw RecordNotFoundException('no session $_where');
    }
  }
}

/// The log of one effect, open for appending: its chunks are rows of
/// `nanoflow_logs`.
///
/// Written in the background, in the order the bytes were added: what is
/// added while a write is under way waits, and goes in one row after it. No
/// error of the database is thrown: [failed] completes with the first, and
/// the log writes nothing more.
final class SqliteEffectLog implements EffectLog {
  SqliteEffectLog._(this._db, this._effectId);

  final Database _db;
  final String _effectId;

  /// The writes, one after another: completes after the last.
  Future<void> _writing = Future.value();

  /// What was added and is not being written yet.
  final _waiting = BytesBuilder(copy: false);

  /// Whether a write of [_waiting] is to come.
  bool _writeScheduled = false;

  int _unwritten = 0;

  final _failed = Completer<Exception>();

  bool _closed = false;

  /// Completes with the error of the first write that failed: a
  /// [SqliteException].
  @override
  Future<Exception> get failed => _failed.future;

  @override
  int get unwritten => _unwritten;

  @override
  void add(List<int> bytes) {
    if (_closed) throw StateError('the log is closed');
    if (_failed.isCompleted || bytes.isEmpty) return;
    _waiting.add(bytes);
    _unwritten += bytes.length;
    if (_writeScheduled) return;
    _writeScheduled = true;
    _writing = _writing.then((_) => _writeWaiting());
  }

  /// Writes what waits, in one row, until nothing does.
  void _writeWaiting() {
    while (_waiting.isNotEmpty && !_failed.isCompleted) {
      final bytes = _waiting.takeBytes();
      try {
        _db.execute(
          'INSERT INTO nanoflow_logs (effect_id, bytes) VALUES (?, ?)',
          [_effectId, bytes],
        );
      } on SqliteException catch (e) {
        _failed.complete(e);
      }
      _unwritten -= bytes.length;
    }
    if (_failed.isCompleted) {
      _waiting.clear();
      _unwritten = 0;
    }
    _writeScheduled = false;
  }

  @override
  Future<void> flush() => _writing;

  @override
  Future<void> close() {
    _closed = true;
    return _writing;
  }
}

/// Inserts a new document of the session [sessionId] holding [value]; gives
/// its id.
String _insertDocument(Database db, String sessionId, Object? value) {
  final document = Document(id: newId(), sessionId: sessionId, value: value);
  db.execute(
    'INSERT INTO nanoflow_documents (id, session_id, json) VALUES (?, ?, ?)',
    [document.id, sessionId, _json(document.toJson())],
  );
  return document.id;
}

void _insertEvent(Database db, String sessionId, KnownEvent event) =>
    db.execute('INSERT INTO nanoflow_events (session_id, json) VALUES (?, ?)', [
      sessionId,
      _json(event.toJson()),
    ]);

/// The owner in the JSON text [text]; `null` when it is not one.
Owner? _ownerOf(Object? text) {
  if (_decode(text) case final Map<String, Object?> json) {
    try {
      return Owner.fromJson(json);
    } on FormatException {
      return null;
    }
  }
  return null;
}

String _json(Object? value) => jsonEncode(value);

/// The JSON value of the text [text]; `null` when it is not JSON.
Object? _decode(Object? text) {
  if (text is! String) return null;
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// The JSON object in the text [text], of a [what]; a [FormatException]
/// when it is not one.
Map<String, Object?> _object(Object? text, String what) {
  if (_decode(text) case final Map<String, Object?> json) return json;
  throw FormatException('the $what is not a JSON object');
}
