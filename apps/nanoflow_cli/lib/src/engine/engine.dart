import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';

import '../program.dart';
import 'carried_data.dart';
import 'progress.dart';
import 'run_driver.dart';

/// Drives the runs of a session, all at once, until every one has ended.
final class Engine {
  /// The engine of the session [store], which goes by [graph] and runs its
  /// steps through [program]; a line for each event goes to [progress], and
  /// the time of each event comes from [clock].
  Engine({
    required SessionHandle store,
    required Graph graph,
    required GraphProgram program,
    required IOSink progress,
    Clock clock = systemClock,
  }) : _session = DrivenSession(
         store: store,
         graph: graph,
         program: program,
         progress: Progress(progress),
         clock: clock,
       );

  final DrivenSession _session;

  /// Drives every unfinished run of the session to its end; returns 0 when
  /// no run failed, 1 otherwise.
  ///
  /// A run that has not started a step starts its first one, which was
  /// created with the run. A run that failed does not stop the others; a run
  /// that splits is followed by the runs it created.
  Future<int> drive() async {
    final store = _session.store;
    final driving = <Future<void>>[];
    for (final run in await store.runs()) {
      final events = await store.events(run.id);
      switch (replay(run.id, events).status) {
        case RunStatus.finished || RunStatus.split:
          break;
        case RunStatus.failed:
          _session.anyFailed = true;
        case RunStatus.pending when run.parentId == null:
          final started = events.first as RunStarted;
          final first = (await store.steps(run.id)).single;
          _session.progress.report(started);
          driving.add(
            RunDriver(
              _session,
              run.id,
            ).drive(first, node: started.node, carried: carriedAtStart(first)),
          );
        case RunStatus.pending || RunStatus.running:
          throw StateError(
            'run ${run.id} was under way before this engine: '
            'it needs recovery',
          );
      }
    }
    await Future.wait(driving);
    return _session.anyFailed ? 1 : 0;
  }

  /// Stops: closes stdin of every running `--call`, waits for them to exit,
  /// writes no further events. [drive] then completes.
  Future<void> stop() async {
    _session.stopping = true;
    final calls = List.of(_session.calls);
    for (final call in calls) {
      call.stop();
    }
    await Future.wait([for (final call in calls) call.ended]);
  }
}
