import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_process/nanoflow_process.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' hide Session;

import 'schema.dart';

/// The sessions in an SQLite database of the app, as the library writes them:
/// a feed of changes, and data on request (storage design §6.6).
///
/// The reader only reads; it creates nothing, and waits while there is no
/// database or no nanoflow tables in it. SQLite tells no other process of a
/// commit, so the reader asks `PRAGMA data_version` every [pollInterval],
/// and when it has changed reads, in one snapshot, what came after what it
/// read last. Whether the process that owns a session is alive it learns
/// from the OS, which tells when the process exits.
///
/// It can run in a process that owns sessions of the same database: there is
/// no lock that reading would drop. It has no files: the paths are `null`.
final class SqliteReader implements SessionReader {
  /// A reader of the database [path] that asks [processes] whether the owners
  /// of sessions are alive. Without [processes] it makes the adapter of this
  /// OS, [Processes.forPlatform], and closes it when the feed is cancelled;
  /// an adapter it is given is the caller's to close.
  SqliteReader(
    String path, {
    this.pollInterval = const Duration(milliseconds: 250),
    Processes? processes,
  }) : path = p.normalize(p.absolute(path)),
       _processes = processes ?? Processes.forPlatform(),
       _ownsProcesses = processes == null;

  /// The database file.
  final String path;

  /// How often the reader asks whether the database has changed.
  final Duration pollInterval;

  final Processes _processes;

  /// Whether the reader made [_processes], and so closes it.
  final bool _ownsProcesses;

  late final Stream<Change> _changes = _follow();

  /// Everything already in the database, then new changes as they appear,
  /// for every session. Single subscription; cancelling stops all watching.
  ///
  /// Each read gives, of what has come since the read before: the new
  /// sessions, newest first; the effects new (`effect-added`) or written again
  /// (`effect-changed`); the events, in the order they were written — a row
  /// that is not a JSON object with string `time` and `event` is
  /// `log-corrupted`; the documents; then, for each session whose journal
  /// goes on, `owner-changed` when its owner or whether it is alive has
  /// changed. A row that is not its model comes as an error, once, and its
  /// entity is not given.
  @override
  Stream<Change> changes() => _changes;

  /// The value of the document [documentId] of the session [sessionId].
  ///
  /// Throws an [ArgumentError] when the database has no such session, and a
  /// [RecordNotFoundException] when the session has no such document.
  @override
  Future<Object?> documentValue(String sessionId, String documentId) async =>
      _reading((db) {
        _checkSession(db, sessionId);
        final rows = db.select(
          'SELECT json FROM nanoflow_documents '
          'WHERE id = ? AND session_id = ?',
          [documentId, sessionId],
        );
        if (rows.isEmpty) {
          throw RecordNotFoundException(
            'no document $documentId in $path#$sessionId',
          );
        }
        return Document.fromJson(_object(rows.single['json'])).value;
      });

  /// The log of the effect [effectId] of the session [sessionId]: the text
  /// written so far, then what is appended, read every [pollInterval], until
  /// cancelled. Decodes UTF-8 across the chunks.
  ///
  /// Errors with an [ArgumentError] when there is no such session or effect.
  @override
  Stream<String> effectLog(String sessionId, String effectId) {
    final out = StreamController<String>();
    Database? db;
    Timer? timer;
    final text = StringBuffer();
    final bytes = const Utf8Decoder(allowMalformed: true)
        .startChunkedConversion(StringConversionSink.fromStringSink(text));
    var last = 0;

    void read() {
      try {
        for (final row in db!.select(
          'SELECT seq, bytes FROM nanoflow_logs '
          'WHERE effect_id = ? AND seq > ? ORDER BY seq',
          [effectId, last],
        )) {
          last = row['seq'] as int;
          bytes.add(row['bytes'] as Uint8List);
        }
      } on Exception catch (error, stack) {
        out.addError(error, stack);
      }
      if (text.isNotEmpty) {
        out.add('$text');
        text.clear();
      }
    }

    out
      ..onListen = () {
        try {
          final open = db = _open();
          _checkSession(open, sessionId);
          final found = open.select(
            'SELECT 1 FROM nanoflow_effects WHERE id = ? AND session_id = ?',
            [effectId, sessionId],
          );
          if (found.isEmpty) {
            throw ArgumentError.value(
              effectId,
              'effectId',
              'no such effect in session $sessionId',
            );
          }
        } on Object catch (error, stack) {
          db?.close();
          db = null;
          out
            ..addError(error, stack)
            ..close();
          return;
        }
        read();
        timer = Timer.periodic(pollInterval, (_) => read());
      }
      ..onCancel = () {
        timer?.cancel();
        db?.close();
      };
    return out.stream;
  }

  @override
  String? sessionPath(String sessionId) => null;

  @override
  String? effectPath(String effectId) => null;

  @override
  String? logPath(String effectId) => null;

  @override
  String? documentPath(String sessionId, String documentId) => null;

  /// The feed: reads whenever the database has changed, or the process of an
  /// owner it watches has exited; stops watching when it is cancelled.
  Stream<Change> _follow() {
    final owners = Owners(_processes);
    final feed = _Feed(owners);
    final out = StreamController<Change>();
    Database? db;
    int? version;
    var due = true;
    Timer? timer;
    StreamSubscription<void>? news;

    void read() {
      try {
        db ??= openForReading(path);
        final open = db;
        if (open == null) return;
        final now = open.select('PRAGMA data_version').single.values.single;
        if (!due && now == version) return;
        version = now as int?;
        due = false;
        inSnapshot(open, () => feed.read(open, out));
      } on Exception catch (error, stack) {
        out.addError(error, stack);
      }
    }

    out
      ..onListen = () {
        news = owners.news.listen((_) => due = true);
        read();
        timer = Timer.periodic(pollInterval, (_) => read());
      }
      ..onCancel = () async {
        timer?.cancel();
        await news?.cancel();
        owners.close();
        db?.close();
        if (_ownsProcesses) await _processes.close();
      };
    return out.stream;
  }

  /// What [read] gives of the database, open for it and closed after.
  T _reading<T>(T Function(Database db) read) {
    final db = _open();
    try {
      return read(db);
    } finally {
      db.close();
    }
  }

  /// The database, open to read; a [RecordNotFoundException] while there is
  /// none.
  Database _open() =>
      openForReading(path) ??
      (throw RecordNotFoundException('no nanoflow database at $path'));

  void _checkSession(Database db, String sessionId) {
    final found = db.select('SELECT 1 FROM nanoflow_sessions WHERE id = ?', [
      sessionId,
    ]);
    if (found.isEmpty) {
      throw ArgumentError.value(sessionId, 'sessionId', 'no session in $path');
    }
  }
}

/// What the feed has given of the database, and how far it has read.
final class _Feed {
  _Feed(this.owners);

  final Owners owners;

  /// The last `seq` read of sessions, events and documents, and `rev` of
  /// effects.
  int _sessions = 0;
  int _events = 0;
  int _documents = 0;
  int _effects = 0;

  /// The ids of the sessions given.
  final Set<String> _given = {};

  /// The ids of the sessions whose last event has been read.
  final Set<String> _ended = {};

  /// The effects given, as last given, by id.
  final Map<String, Effect> _effectsGiven = {};

  /// Gives to [out] what [db] has that came after the read before; [db] is
  /// in a snapshot.
  void read(Database db, StreamSink<Change> out) {
    for (final row in db.select(
      'SELECT seq, json FROM nanoflow_sessions WHERE seq > ? '
      'ORDER BY created DESC, seq DESC',
      [_sessions],
    )) {
      final seq = row['seq'] as int;
      if (seq > _sessions) _sessions = seq;
      final session = _model(row['json'], Session.fromJson, out);
      if (session == null) continue;
      _given.add(session.id);
      out.add(SessionAdded(session));
    }
    for (final row in db.select(
      'SELECT rev, session_id, json FROM nanoflow_effects WHERE rev > ? '
      'ORDER BY rev',
      [_effects],
    )) {
      _effects = row['rev'] as int;
      if (!_given.contains(row['session_id'])) continue;
      final effect = _model(row['json'], Effect.fromJson, out);
      if (effect == null) continue;
      final known = _effectsGiven[effect.id];
      if (known == effect) continue;
      _effectsGiven[effect.id] = effect;
      out.add(known == null ? EffectAdded(effect) : EffectChanged(effect));
    }
    for (final row in db.select(
      'SELECT seq, session_id, json FROM nanoflow_events WHERE seq > ? '
      'ORDER BY seq',
      [_events],
    )) {
      _events = row['seq'] as int;
      final sessionId = row['session_id'] as String;
      if (!_given.contains(sessionId)) continue;
      final change = _eventChange(sessionId, row['json'], () {
        // The number of the event in the journal, from 1: counted only for
        // one that is corrupted.
        final before = db.select(
          'SELECT count(*) AS n FROM nanoflow_events '
          'WHERE session_id = ? AND seq < ?',
          [sessionId, row['seq']],
        );
        return (before.single['n'] as int) + 1;
      });
      if (change case EventAdded(event: SessionFinished() || SessionFailed())) {
        _ended.add(sessionId);
      }
      out.add(change);
    }
    for (final row in db.select(
      'SELECT seq, id, session_id FROM nanoflow_documents WHERE seq > ? '
      'ORDER BY seq',
      [_documents],
    )) {
      _documents = row['seq'] as int;
      final sessionId = row['session_id'] as String;
      if (!_given.contains(sessionId)) continue;
      out.add(
        DocumentAdded(sessionId: sessionId, documentId: row['id'] as String),
      );
    }
    final recorded = {
      for (final row in db.select(
        'SELECT session_id, json FROM nanoflow_owners',
      ))
        row['session_id'] as String: row['json'],
    };
    for (final sessionId in _given) {
      if (_ended.contains(sessionId)) {
        owners.drop(sessionId);
        continue;
      }
      final record = _ownerRecord(recorded[sessionId]);
      if (owners.observe(sessionId, record) case final observed?) {
        owners.tell(observed, out);
      }
    }
  }
}

/// The change the event row [json] of the session [sessionId] gives: an
/// event, or `log-corrupted` with the number [lineOf] gives when it is not a
/// JSON object with string `time` and `event`.
Change _eventChange(String sessionId, Object? json, int Function() lineOf) {
  if (_decode(json) case final Map<String, Object?> event
      when event['time'] is String && event['event'] is String) {
    return EventAdded(sessionId: sessionId, event: Event.fromJson(event));
  }
  return LogCorrupted(
    sessionId: sessionId,
    line: lineOf(),
    text: json is String ? json : '$json',
  );
}

/// The owner a row of `nanoflow_owners` records: none without a row, and
/// `null` when the row is not an owner.
({Owner? owner})? _ownerRecord(Object? json) {
  if (json == null) return (owner: null);
  if (_decode(json) case final Map<String, Object?> object) {
    try {
      return (owner: Owner.fromJson(object));
    } on FormatException {
      return null;
    }
  }
  return null;
}

/// The model in the JSON text [json], read with [fromJson]; `null`, with the
/// error given to [out], when it is not one.
T? _model<T>(
  Object? json,
  T Function(Map<String, Object?> json) fromJson,
  StreamSink<Change> out,
) {
  try {
    return fromJson(_object(json));
  } on FormatException catch (error, stack) {
    out.addError(error, stack);
    return null;
  }
}

/// The JSON value of the text [text]; `null` when it is not JSON.
Object? _decode(Object? text) {
  if (text is! String) return null;
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// The JSON object in the text [text]; a [FormatException] when it is not
/// one.
Map<String, Object?> _object(Object? text) {
  if (_decode(text) case final Map<String, Object?> json) return json;
  throw const FormatException('not a JSON object');
}
