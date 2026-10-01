import 'package:path/path.dart' as p;

import 'ids.dart';
import 'time.dart';

/// Directory next to the graph file that holds the graph's sessions.
const runsDirName = 'runs';

/// File in a session directory with the session's fields.
const sessionFileName = 'session.json';

/// Directory in a session directory with the session's documents.
const documentsDirName = 'documents';

/// File in a run directory with the run's fields.
const runFileName = 'run.json';

/// File in a run directory with the run's events, one JSON object per line.
const eventsFileName = 'log.jsonl';

/// Directory in a run directory with the run's steps.
const stepsDirName = 'steps';

/// File in a step directory with the step's fields.
const stepFileName = 'step.json';

/// File in a step directory with the output of the step's command.
const logFileName = 'command.log';

const _idLength = 36;

final RegExp _sessionTime = RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-');

final RegExp _nameUnsafe = RegExp(r'[^A-Za-z0-9._-]', unicode: true);

/// UTC time to the millisecond: `2026-09-20T14-03-11-470`.
String _millisecondStamp(DateTime t) =>
    formatTime(t).substring(0, 23).replaceAll(RegExp(r'[:.]'), '-');

/// UTC time to the second: `2026-09-20T14-03-11`.
String _secondStamp(DateTime t) => _millisecondStamp(t).substring(0, 19);

/// Name of a session directory: `review-2026-09-20T14-03-11-<id>`.
String sessionDirName(String graphName, DateTime createdAt, String id) =>
    '$graphName-${_secondStamp(createdAt)}-$id';

/// Name of a run directory: `2026-09-20T14-03-11-470-<id>`.
String runDirName(DateTime createdAt, String id) =>
    '${_millisecondStamp(createdAt)}-$id';

/// Name of a step directory: `2026-09-20T14-03-11-482-collect-<id>`.
///
/// Characters of [node] outside `[A-Za-z0-9._-]` become `_`, one for each.
String stepDirName(DateTime startedAt, String node, String id) =>
    '${_millisecondStamp(startedAt)}-${node.replaceAll(_nameUnsafe, '_')}-$id';

/// Name of a document file: `<id>.json`.
String documentFileName(String id) => '$id.json';

/// The id at the end of a session, run or step directory name, or `null`.
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

/// Whether [dirName] is `<graphName>-YYYY-MM-DDTHH-MM-SS-<id>` exactly.
///
/// A graph's sessions are found by name, so graph `review` must not match the
/// sessions of graph `review-x`.
bool isSessionDirOf(String dirName, String graphName) {
  final prefix = '$graphName-';
  if (!dirName.startsWith(prefix)) return false;
  final rest = dirName.substring(prefix.length);
  final time = _sessionTime.matchAsPrefix(rest);
  return time != null && isId(rest.substring(time.end));
}

/// The graph's name: its file name without the extension.
String graphNameOf(String graphFile) => p.basenameWithoutExtension(graphFile);

/// The directory with the graph's sessions: `runs` next to [graphFile].
String runsDirOf(String graphFile) => p.join(p.dirname(graphFile), runsDirName);
