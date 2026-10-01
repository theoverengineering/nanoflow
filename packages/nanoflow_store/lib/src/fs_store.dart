import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import 'atomic.dart';
import 'session_handle.dart';

/// A node of the graph's `start`, and whether it declares `in`.
typedef StartNode = ({String node, bool takesInput});

/// The sessions in a `runs` directory, as the engine keeps them.
final class FsStore {
  FsStore(this.runsDir, {this._clock = systemClock});

  /// The `runs` directory next to the graph file.
  final String runsDir;

  final Clock _clock;

  /// Creates a session of the graph [graphName] that holds [graph].
  ///
  /// Builds the whole session under `runs/.tmp-<id>/` and renames it into
  /// place: `session.json`, the `documents` directory with the input document
  /// (when [input] is given), and for every start node a run (`run.json`,
  /// `log.jsonl` with `run-started`) with its first step, whose `inputId` is
  /// the input document if the node takes input, else `null`. The session
  /// directory's name holds the time the session is created; creates [runsDir]
  /// when there is none.
  Future<SessionHandle> createSession({
    required String graphName,
    required Map<String, Object?> graph,
    required List<StartNode> startNodes,
    ({Object? value})? input,
  }) async {
    final session = Session(id: newId(), graph: graph);
    final createdAt = _clock();
    final dir = await buildDirAtomically(
      runsDir,
      id: session.id,
      name: sessionDirName(graphName, createdAt, session.id),
      build: (dir) async {
        await writeJsonAtomically(
          p.join(dir, sessionFileName),
          session.toJson(),
        );
        await Directory(p.join(dir, documentsDirName)).create();
        final handle = sessionHandleAt(dir, session, _clock);
        final inputId = input == null
            ? null
            : await handle.writeDocument(input.value);
        for (final start in startNodes) {
          await handle.createRun(
            parentId: null,
            node: start.node,
            inputId: start.takesInput ? inputId : null,
          );
        }
      },
    );
    return sessionHandleAt(dir, session, _clock);
  }

  /// The session [sessionId], or `null` when [runsDir] has none.
  ///
  /// The session's directory is the one whose name ends with the id; a name
  /// that starts with `.` belongs to a session that was never finished being
  /// created. Cuts an incomplete last line off the journal of each run.
  Future<SessionHandle?> openSession(String sessionId) async {
    final runs = Directory(runsDir);
    if (!await runs.exists()) return null;
    await for (final entity in runs.list()) {
      if (idOfBuiltDir(entity) == sessionId) {
        return loadSessionHandle(entity.path, _clock);
      }
    }
    return null;
  }
}
