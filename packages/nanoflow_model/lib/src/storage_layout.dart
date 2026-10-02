import 'package:path/path.dart' as p;

import 'ids.dart';
import 'time.dart';

/// Directory in the project directory that holds the sessions.
const runsDirName = 'runs';

/// File in a session directory with the session's fields.
const sessionFileName = 'session.json';

/// Directory in a session directory with the session's documents.
const documentsDirName = 'documents';

/// File in a session directory with the session's events, one JSON object
/// per line.
const eventsFileName = 'log.jsonl';

/// Directory in a session directory with the session's steps.
const stepsDirName = 'steps';

/// File in a step directory with the step's fields.
const stepFileName = 'step.json';

/// File in a step directory with what the step printed.
const logFileName = 'step.log';

/// File in a session directory whose lock the process that owns the session
/// holds. Its name starts with `.`: readers skip it.
const ownerLockFileName = '.owner.lock';

const _idLength = 36;

final RegExp _sessionDirName = RegExp(
  r'^.+-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-(.{36})$',
);

final RegExp _nameUnsafe = RegExp(r'[^A-Za-z0-9._-]', unicode: true);

/// UTC time to the millisecond: `2026-10-03T10-00-00-482`.
String _millisecondStamp(DateTime t) =>
    formatTime(t).substring(0, 23).replaceAll(RegExp(r'[:.]'), '-');

/// UTC time to the second: `2026-10-03T10-00-00`.
String _secondStamp(DateTime t) => _millisecondStamp(t).substring(0, 19);

/// [name] with each character outside `[A-Za-z0-9._-]` replaced by `_`.
String _safe(String name) => name.replaceAll(_nameUnsafe, '_');

/// Name of a session directory: `review-2026-10-03T10-00-00-<id>`.
///
/// Characters of [workflow] outside `[A-Za-z0-9._-]` become `_`, one for
/// each.
String sessionDirName(String workflow, DateTime createdAt, String id) =>
    '${_safe(workflow)}-${_secondStamp(createdAt)}-$id';

/// Name of a step directory: `2026-10-03T10-00-00-482-collect-<id>`.
///
/// Characters of [name] outside `[A-Za-z0-9._-]` become `_`, one for each.
String stepDirName(DateTime startedAt, String name, String id) =>
    '${_millisecondStamp(startedAt)}-${_safe(name)}-$id';

/// Name of a document file: `<id>.json`.
String documentFileName(String id) => '$id.json';

/// The id at the end of a session or step directory name, or `null`.
///
/// The id is the last 36 characters of [name]; they must form a valid id
/// ([isId]) and be preceded by `-`.
String? idOfDirName(String name) {
  if (name.length <= _idLength || name[name.length - _idLength - 1] != '-') {
    return null;
  }
  final id = name.substring(name.length - _idLength);
  return isId(id) ? id : null;
}

/// Whether [name] is `<workflow>-YYYY-MM-DDTHH-MM-SS-<id>` exactly, with a
/// workflow of at least one character.
bool isSessionDirName(String name) {
  final match = _sessionDirName.firstMatch(name);
  return match != null && isId(match.group(1)!);
}

/// The directory with the sessions: `runs` in [projectDir].
String runsDirOf(String projectDir) => p.join(projectDir, runsDirName);
