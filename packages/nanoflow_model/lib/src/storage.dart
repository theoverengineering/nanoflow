// The port of the storage of sessions (storage design §6.2): what the library
// writes through and what readers read through. The adapters are packages of
// their own, which depend on this one and on no other adapter: the files of
// `runs/` (nanoflow_store, nanoflow_reader) and an SQLite database
// (nanoflow_sqlite).

import 'changes.dart';
import 'entities.dart';
import 'events.dart';
import 'owner.dart';

/// The sessions of a project, as the process that runs them keeps them.
///
/// A failure of the storage is any [Exception] its methods, and those of the
/// sessions it gives, throw, but [SessionBusyException] and
/// [SessionExistsException].
abstract interface class SessionStore {
  /// Creates a session of the workflow [workflow]: one call of it, owned by
  /// this process.
  ///
  /// The session appears whole, or not at all: its fields with [graph], the
  /// input document when [input] is given, and a journal whose one event is
  /// `session-started` with [code], at the time the session is created. Its
  /// id is [id] when given, else a new one. [owner] is recorded as the
  /// session's owner; `null` records none.
  ///
  /// Throws a [SessionExistsException], having written nothing, when the
  /// storage has a session [id] already.
  Future<OpenSession> createSession({
    required String workflow,
    required Map<String, Object?>? graph,
    required ({Object? value})? input,
    required String? code,
    String? id,
    Owner? owner,
  });

  /// The session [sessionId], now owned by this process with [owner]
  /// recorded as its owner; `null` when the storage has no such session.
  ///
  /// Throws a [SessionBusyException], having changed nothing, when another
  /// process owns the session and runs, or this isolate owns it already.
  /// Then cuts off the journal what a process that died left of an event.
  Future<OpenSession?> openSession(String sessionId, {Owner? owner});

  /// Ids of the sessions of [workflow] whose journal has no
  /// `session-finished` or `session-failed`, newest first: by the time of
  /// their `session-started`.
  ///
  /// Owns none of them: a session another process owns is listed too. A
  /// session that cannot be read is left out.
  Future<List<String>> unfinishedSessions(String workflow);
}

/// One session that this process owns: what it writes, and what it reads
/// back to continue the session after a crash.
///
/// Only one process works with a session at a time: this one, until
/// [release] or the end of the process.
abstract interface class OpenSession {
  /// The session's fields.
  Session get session;

  /// The events of the session, in the order they were written.
  ///
  /// An event still being written is left out. Throws a
  /// [StoreCorruptedException] for one that is not a JSON object; an object
  /// that is not an event this version knows is an [UnknownEvent].
  Future<List<Event>> events();

  /// The records of the session's effects, in the order they were created.
  Future<List<Effect>> effects();

  /// The value of the document [documentId].
  Future<Object?> documentValue(String documentId);

  /// Creates the record of an effect, without `outputId`; writes no event.
  Future<Effect> createEffect({
    required String name,
    required String key,
    required String? after,
    required String? place,
  });

  /// Appends [event] to the session's journal.
  ///
  /// Events given before this one is appended — by effects that run side by
  /// side — are appended after it, in the order given.
  Future<void> appendEvent(KnownEvent event);

  /// Writes a new document holding [value]; returns its id.
  Future<String> writeDocument(Object? value);

  /// Rewrites the record of [effect] with [outputId]; returns the effect as
  /// it is now.
  Future<Effect> setEffectOutput(Effect effect, String outputId);

  /// Rewrites the record of [effect] with [after]; returns the effect as it
  /// is now.
  Future<Effect> setEffectAfter(Effect effect, String? after);

  /// Opens the log of the effect [effectId] for appending: an effect that
  /// runs again adds to the log it has.
  ///
  /// Throws an [ArgumentError] for an effect the session does not have.
  EffectLog openLog(String effectId);

  /// Gives the session up: it has no owner any more, and another process may
  /// own it from now on. Reading through this still works; writing through it
  /// must not be done any more.
  Future<void> release();
}

/// The log of one effect, open for appending.
///
/// It is written in the background, in the order the bytes were added. No
/// error of the storage is thrown, now or later: when the log cannot be
/// written, [failed] completes with why, and the log writes nothing more.
abstract interface class EffectLog {
  /// Completes with the error of the first write of the log that failed.
  Future<Exception> get failed;

  /// How many of the bytes added so far are not written yet: 0 once the log
  /// has failed, as it drops them.
  int get unwritten;

  /// Adds [bytes] to the end of the log. They are not copied: [bytes] must
  /// not change afterwards.
  void add(List<int> bytes);

  /// Completes once everything added so far is written, or the log has
  /// failed.
  Future<void> flush();

  /// Writes what is left and closes the log.
  Future<void> close();
}

/// Every session of a storage, as the library writes them: a feed of
/// changes, and data on request. It only reads.
abstract interface class SessionReader {
  /// Everything already stored, then new changes as they appear, for every
  /// session. Single subscription; cancelling stops all watching. Works
  /// while the storage has nothing yet.
  ///
  /// The events of a session come in the order of its journal, after the
  /// session's `session-added`; anything else may come in any order. An
  /// event still being written is given once it is complete. Something
  /// stored that is not its model comes as an error on the stream, once, and
  /// the entity is not given until it is fixed; the feed goes on.
  ///
  /// While a session's journal goes on, `owner-changed` tells its owner and
  /// whether the owner's process is alive: first after the session's other
  /// changes of the first read, then each time either changes. A session
  /// that ended comes with its last event and no `owner-changed` that says
  /// its owner is gone.
  Stream<Change> changes();

  /// The value of the document [documentId] of the session [sessionId].
  Future<Object?> documentValue(String sessionId, String documentId);

  /// The log of the effect [effectId] of the session [sessionId]: the text
  /// written so far, then what is appended, until cancelled. Decodes UTF-8
  /// across the chunks.
  Stream<String> effectLog(String sessionId, String effectId);

  // Files of a storage that has them, known once the feed has given the
  // entity; `null` before, and always for a storage without files.

  /// The directory of the session [sessionId].
  String? sessionPath(String sessionId);

  /// The directory of the effect [effectId].
  String? effectPath(String effectId);

  /// The log file of the effect [effectId], which may not exist yet.
  String? logPath(String effectId);

  /// The file of the document [documentId] of the session [sessionId].
  String? documentPath(String sessionId, String documentId);
}

/// Another process owns the session, or this one does already.
final class SessionBusyException implements Exception {
  const SessionBusyException(this.sessionId);

  final String sessionId;

  @override
  String toString() =>
      'SessionBusyException: another process owns the session $sessionId, '
      'or this one does already';
}

/// A session was to be created with an id the storage has already.
final class SessionExistsException implements Exception {
  const SessionExistsException(this.sessionId);

  final String sessionId;

  @override
  String toString() =>
      'SessionExistsException: there is a session $sessionId already';
}

/// A journal has an event that is not a JSON object.
final class StoreCorruptedException implements Exception {
  const StoreCorruptedException({required this.path, required this.line});

  /// Where the journal is: its file, or `<database>#<session id>`.
  final String path;

  /// The number of the event, from 1.
  final int line;

  @override
  String toString() =>
      'StoreCorruptedException: line $line of $path is not a JSON object';
}
