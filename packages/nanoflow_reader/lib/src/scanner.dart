import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_process/nanoflow_process.dart';
import 'package:path/path.dart' as p;

import 'tail.dart';

/// The sessions of a `runs` directory as far as the feed has given them.
///
/// Each [scan] goes through the tree once and gives what has appeared since
/// the scan before. Names that start with `.` are skipped in the listings of
/// directories: the store builds files and directories under such names and
/// renames them into place once they are complete. The one such file a scan
/// reads, a session's `.owner.lock`, it opens by its path.
///
/// What has ended is not looked at again: nothing is written to a session
/// after its last event (`session-finished`, `session-failed`). A session is
/// read once more after the scan that read its last event: that scan may
/// have listed the session's effects before the last of them was put in place.
///
/// The owner of a session whose journal goes on is looked at in every scan
/// before its journal is read, and told by [owners] after it.
final class Scanner {
  Scanner({required this.runsDir, required this.owners});

  final String runsDir;

  final Owners owners;

  /// The sessions given, by directory.
  final Map<String, _Session> _sessions = {};

  /// The sessions and effects given, by id.
  final Map<String, _Session> _sessionsById = {};
  final Map<String, _Effect> _effectsById = {};

  /// Paths whose problem has been given as an error: it is given once.
  final Set<String> _reported = {};

  /// Gives to [out] what has appeared since the scan before: for each
  /// session, newest first, `session-added` (once), then its new effects and an
  /// `effect-changed` for an effect whose `effect.json` was rewritten — with
  /// the `outputId` of its `effect-finished`, or with another `after` when it
  /// runs again — its journal's new complete lines, then its new documents,
  /// then, while its journal goes on, `owner-changed` when its owner or whether
  /// it is alive has changed (see [Owners]).
  ///
  /// Newest first: a feed of a long history gives first the sessions that
  /// are likely to be looked at.
  ///
  /// A file that is not there yet is looked for again by the next scan. A
  /// file or directory that cannot be read, or a file that is not its model,
  /// is given to [out] as an error, once, and is looked at again by the next
  /// scans too.
  Future<void> scan(EventSink<Change> out) async {
    final sessions = await _attempt(
      runsDir,
      out,
      () => builtDirs(runsDir, isSessionDirName),
    );
    final newestFirst = [...?sessions]
      ..sort((a, b) {
        final byTime = _createdStamp(b).compareTo(_createdStamp(a));
        return byTime != 0 ? byTime : b.compareTo(a);
      });
    for (final dir in newestFirst) {
      await _scanSession(dir, out);
    }
  }

  String? sessionPath(String sessionId) => _sessionsById[sessionId]?.dir;

  String? effectPath(String effectId) => _effectsById[effectId]?.dir;

  String? logPath(String effectId) {
    final effect = _effectsById[effectId];
    return effect == null ? null : p.join(effect.dir, effect.effect.log);
  }

  String? documentPath(String sessionId, String documentId) {
    final session = _sessionsById[sessionId];
    return session == null || !session.documents.contains(documentId)
        ? null
        : p.join(session.dir, documentsDirName, documentFileName(documentId));
  }

  Future<void> _scanSession(String dir, EventSink<Change> out) async {
    var session = _sessions[dir];
    if (session != null && session.ended) return;
    if (session == null) {
      final model = await _readModel(
        p.join(dir, sessionFileName),
        Session.fromJson,
        out,
      );
      if (model == null) return;
      session = _sessions[dir] = _sessionsById[model.id] = _Session(model, dir);
      out.add(SessionAdded(model));
    }
    final sessionId = session.session.id;
    // Whether its last event was read before this scan listed its effects:
    // then the listing has every effect it has.
    final lastRead = session.lastRead;
    final effectsDir = p.join(dir, effectsDirName);
    final effects = await _attempt(
      effectsDir,
      out,
      () => builtDirs(effectsDir),
    );
    for (final effectDir in effects ?? const <String>[]) {
      await _scanEffect(session, effectDir, out);
    }
    // Looked at before the journal is read, and told after it only while the
    // journal goes on: an owner that has let the session go, or exited, by
    // now wrote all it did, its last event too, and the journal read next
    // has it.
    final lockFile = p.join(dir, ownerLockFileName);
    final owner = lastRead
        ? null
        : await _attempt(
            lockFile,
            out,
            () async => owners.observe(sessionId, await _ownerRecord(lockFile)),
          );
    final journal = session.journal;
    final lines = await _attempt(journal.path, out, journal.readLines);
    for (final (:number, :bytes) in lines ?? const <Line>[]) {
      final change = _journalChange(sessionId, number, bytes);
      switch (change) {
        case EventAdded(event: EffectStarted(:final effectId)):
          session.effectStarted(effectId);
        case EventAdded(
          event: EffectFinished(:final effectId, :final outputId),
        ):
          session.effectEnded(effectId, outputId);
        case EventAdded(event: EffectFailed(:final effectId)):
          session.effectEnded(effectId, null);
        case EventAdded(event: SessionFinished() || SessionFailed()):
          session.lastRead = true;
        default:
      }
      out.add(change);
    }
    // A session written by hand may have no documents directory.
    final documentsDir = p.join(dir, documentsDirName);
    final documents = await _attempt(
      documentsDir,
      out,
      () => _documentIds(documentsDir),
    );
    for (final documentId in documents ?? const <String>[]) {
      if (session.documents.add(documentId)) {
        out.add(DocumentAdded(sessionId: sessionId, documentId: documentId));
      }
    }
    if (session.lastRead) {
      owners.drop(sessionId);
    } else if (owner != null) {
      owners.tell(owner, out);
    }
    session.ended =
        lastRead &&
        effects != null &&
        effects.every(session.effects.containsKey) &&
        !session.effects.values.any(session.mayChange) &&
        documents != null;
  }

  /// Gives an effect that is new, or an effect given before whose `effect.json`
  /// may have been rewritten since (see [_Session.mayChange]) when it has been.
  Future<void> _scanEffect(
    _Session session,
    String dir,
    EventSink<Change> out,
  ) async {
    final known = session.effects[dir];
    if (known != null && !session.mayChange(known)) return;
    final effect = await _readModel(
      p.join(dir, effectFileName),
      Effect.fromJson,
      out,
    );
    if (effect == null) return;
    // The journal is read after the effects: these are the `effect-started`
    // read before this read of `effect.json`.
    final starts = session.startsOf(effect.id);
    if (known == null) {
      session.effects[dir] = _effectsById[effect.id] = _Effect(effect, dir)
        ..startsRead = starts;
      out.add(EffectAdded(effect));
      return;
    }
    known.startsRead = starts;
    if (effect != known.effect) {
      known.effect = effect;
      out.add(EffectChanged(effect));
    }
  }

  /// The model in the file at [path], or `null` when it is not there or
  /// cannot be read.
  Future<T?> _readModel<T>(
    String path,
    T Function(Map<String, Object?> json) fromJson,
    EventSink<Change> out,
  ) => _attempt(path, out, () => readModel(path, fromJson));

  /// What [read] of [path] gives, or `null` when [path] is not there, or
  /// when [read] fails, which is given to [out] as an error once for [path].
  Future<T?> _attempt<T>(
    String path,
    EventSink<Change> out,
    Future<T> Function() read,
  ) async {
    try {
      return await read();
    } on PathNotFoundException {
      return null;
    } on IOException catch (error, stack) {
      if (_reported.add(path)) out.addError(error, stack);
    } on FormatException catch (error, stack) {
      if (_reported.add(path)) out.addError(error, stack);
    }
    return null;
  }
}

/// The directories in [parent] that [accepts] by name, in name order: by
/// default those whose name ends with an id.
///
/// Throws a [PathNotFoundException] when there is no [parent].
Future<List<String>> builtDirs(
  String parent, [
  bool Function(String name) accepts = _endsWithId,
]) async => [
  for (final entity in await _visibleEntries(parent))
    if (entity is Directory && accepts(_name(entity))) entity.path,
]..sort();

/// Reads the model in the JSON file at [path] with [fromJson].
///
/// Throws a [FormatException] whose message starts with [path] when the file
/// is not a JSON object in UTF-8 or not the model's JSON form.
Future<T> readModel<T>(
  String path,
  T Function(Map<String, Object?> json) fromJson,
) async {
  final bytes = await File(path).readAsBytes();
  try {
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, Object?>) {
      throw const FormatException('expected a JSON object');
    }
    return fromJson(json);
  } on FormatException catch (e) {
    throw FormatException('$path: ${e.message}');
  }
}

/// The owner the `.owner.lock` at [path] records: none when the file is not
/// there or empty, and `null` when it does not hold an owner, as while a new
/// record is written over the old one. Throws an [IOException] when the file
/// cannot be read.
Future<({Owner? owner})?> _ownerRecord(String path) async {
  final Uint8List bytes;
  try {
    bytes = await File(path).readAsBytes();
  } on PathNotFoundException {
    return (owner: null);
  }
  if (bytes.isEmpty) return (owner: null);
  try {
    if (jsonDecode(utf8.decode(bytes)) case final Map<String, Object?> json) {
      return (owner: Owner.fromJson(json));
    }
  } on FormatException {
    // Not JSON, or not an owner.
  }
  return null;
}

/// The time to the second in the name of the session directory [dir]:
/// `YYYY-MM-DDTHH-MM-SS`, which sorts as the time does.
String _createdStamp(String dir) {
  final name = _name(Directory(dir));
  // `<workflow>-<stamp>-<id>`: the stamp is 19 characters before `-<id>`.
  return name.substring(name.length - 56, name.length - 37);
}

/// The ids of the documents in the `documents` directory [dir], in name
/// order.
Future<List<String>> _documentIds(String dir) async => [
  for (final entity in await _visibleEntries(dir))
    if (entity is File)
      if (p.basenameWithoutExtension(entity.path) case final id
          when isId(id) && _name(entity) == documentFileName(id))
        id,
]..sort();

/// The entries of [dir] whose name does not start with `.`: the store builds
/// files and directories under such names.
Future<List<FileSystemEntity>> _visibleEntries(String dir) async => [
  for (final entity in await Directory(dir).list().toList())
    if (!_name(entity).startsWith('.')) entity,
];

/// The change a complete [line] of the journal of the session [sessionId]
/// gives: an event, or `log-corrupted` when the line is not a JSON object
/// with string `time` and `event`. [number] counts lines from 1.
Change _journalChange(String sessionId, int number, Uint8List line) {
  if (_decode(line) case final Map<String, Object?> json
      when json['time'] is String && json['event'] is String) {
    return EventAdded(sessionId: sessionId, event: Event.fromJson(json));
  }
  return LogCorrupted(
    sessionId: sessionId,
    line: number,
    text: utf8.decode(line, allowMalformed: true),
  );
}

/// The JSON value in [line], or `null` when it is not JSON in UTF-8.
Object? _decode(Uint8List line) {
  try {
    return jsonDecode(utf8.decode(line));
  } on FormatException {
    return null;
  }
}

String _name(FileSystemEntity entity) => p.basename(entity.path);

bool _endsWithId(String name) => idOfDirName(name) != null;

/// A session given, with what of it has been given.
final class _Session {
  _Session(this.session, this.dir)
    : journal = Tail(p.join(dir, eventsFileName));

  final Session session;

  final String dir;

  /// Its journal, read up to the end of the last complete line.
  final Tail journal;

  /// Its effects, by directory.
  final Map<String, _Effect> effects = {};

  /// How many `effect-started` of each of its effects have been read, by id.
  final Map<String, int> _starts = {};

  /// Ids of its effects whose last event read is `effect-started`.
  final Set<String> _running = {};

  /// The `outputId` of the last `effect-finished` read of each of its effects,
  /// by id.
  final Map<String, String> _outputs = {};

  /// Ids of its documents.
  final Set<String> documents = {};

  /// Whether its last event has been read.
  bool lastRead = false;

  /// Whether it has been read in full since its last event was: nothing
  /// more is written to it.
  bool ended = false;

  /// Takes the `effect-started` of the effect [effectId].
  void effectStarted(String effectId) {
    _starts.update(effectId, (n) => n + 1, ifAbsent: () => 1);
    _running.add(effectId);
  }

  /// Takes the `effect-finished` with [outputId], or the `effect-failed`
  /// (`null`), of the effect [effectId].
  void effectEnded(String effectId, String? outputId) {
    _running.remove(effectId);
    if (outputId != null) _outputs[effectId] = outputId;
  }

  /// How many `effect-started` of the effect [effectId] have been read.
  int startsOf(String effectId) => _starts[effectId] ?? 0;

  /// Whether the `effect.json` of [given] may have been rewritten since it
  /// was read, and so is read again (D3):
  /// - it was given without the `outputId` of its last `effect-finished`:
  ///   `effect.json` is rewritten with it after that event is written;
  /// - it runs again (an `effect-started` that is not its first), and
  ///   `effect.json` is rewritten with the `after` of the new call right after
  ///   that event: read again while that run goes on, and once after an
  ///   `effect-started` read since `effect.json` was.
  bool mayChange(_Effect given) {
    final id = given.effect.id;
    final output = _outputs[id];
    if (output != null && given.effect.outputId != output) return true;
    final starts = startsOf(id);
    return starts > 1 && (starts > given.startsRead || _running.contains(id));
  }
}

/// An effect given, as it was last given.
final class _Effect {
  _Effect(this.effect, this.dir);

  Effect effect;

  final String dir;

  /// How many `effect-started` of it had been read when its `effect.json` was
  /// last read.
  int startsRead = 0;
}
