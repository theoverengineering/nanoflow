import 'dart:async';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';

import '../program.dart';
import 'progress.dart';
import 'recovery.dart';
import 'run_driver.dart';

/// Drives the runs of a session, all at once, until every one has ended.
final class Engine {
  /// The engine of the session [store], which goes by [graph] and runs its
  /// steps through [program]; a line for each event goes to [progress], and
  /// the time of each event comes from [clock]. [stop] waits [stopTimeout]
  /// for the running steps to stop before it kills them.
  Engine({
    required SessionHandle store,
    required Graph graph,
    required GraphProgram program,
    required IOSink progress,
    Clock clock = systemClock,
    this.stopTimeout = const Duration(seconds: 10),
  }) : _session = DrivenSession(
         store: store,
         graph: graph,
         program: program,
         progress: Progress(progress),
         clock: clock,
       );

  final DrivenSession _session;

  /// How long [stop] waits for the running `--call`s to exit on their own.
  final Duration stopTimeout;

  /// Drives every unfinished run of the session to its end; returns 0 when
  /// no run failed, 1 otherwise.
  ///
  /// Each run goes on from where its journal and its steps say it stopped
  /// ([resumptionsOf]): a run of a new session starts its first step, which
  /// was created with it. A run that failed does not stop the others; a run
  /// that splits is followed by the runs it created.
  Future<int> drive() async {
    final driving = <Future<void>>[];
    for (final run in await resumptionsOf(_session.store, _session.graph)) {
      switch (run) {
        case RunEnded(:final failed):
          if (failed) _session.anyFailed = true;
        case RunInSplit():
          break;
        case RunAtStep(:final runId, :final step, :final node, :final carried):
          if (run.started case final started?) {
            _session.progress.report(started);
          }
          driving.add(
            RunDriver(
              _session,
              runId,
            ).drive(step, node: node, carried: carried),
          );
        case RunAfterStep(:final runId, :final step, :final node):
          driving.add(
            RunDriver(
              _session,
              runId,
              nextStep: run.nextStep,
              children: run.children,
            ).goOn(step, node: node, result: run.result, carried: run.carried),
          );
      }
    }
    await Future.wait(driving);
    return _session.anyFailed ? 1 : 0;
  }

  /// Stops: writes no further events, and closes stdin of every running
  /// `--call`, which then stops its command and exits. A call that has not
  /// exited after [stopTimeout] is killed. [drive] then completes.
  Future<void> stop() async {
    _session.stopping = true;
    for (final call in List.of(_session.calls)) {
      call.stop();
    }
    try {
      await _callsEnded().timeout(stopTimeout);
    } on TimeoutException {
      for (final call in List.of(_session.calls)) {
        call.kill();
      }
      await _callsEnded();
    }
  }

  Future<void> _callsEnded() =>
      Future.wait([for (final call in List.of(_session.calls)) call.ended]);
}
