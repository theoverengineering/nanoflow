import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';

/// The course of a session for a human: a line for each event, on the
/// engine's stderr.
///
/// A line is `<HH:MM:SS local> <run id first 4> <event> <details>`; the time
/// is the event's. The event and its details:
///
/// - `run-started <node>`
/// - `step-started <node>`
/// - `step-finished <node> exit <code>`
/// - `run-split <child4> <node>, <child4> <node>`: the runs it created
/// - `run-finished`
/// - `run-failed <error>`
final class Progress {
  Progress(this._sink);

  final IOSink _sink;

  /// Writes the line of [event].
  ///
  /// [node] is the node of the step of a `step-finished`; [children] are the
  /// `run-started` of the runs a `run-split` created, in the order they were
  /// created.
  void report(
    KnownEvent event, {
    String? node,
    List<RunStarted> children = const [],
  }) {
    final details = switch (event) {
      RunStarted(:final node) || StepStarted(:final node) => node,
      StepFinished(:final exitCode) => '$node exit $exitCode',
      RunSplit() => [
        for (final child in children) '${_short(child.runId)} ${child.node}',
      ].join(', '),
      RunFinished() => null,
      RunFailed(:final error) => error,
    };
    _sink.writeln(
      [_clock(event.time), _short(event.runId), event.name, ?details].join(' '),
    );
  }
}

/// The first 4 characters of [id].
String _short(String id) => id.substring(0, 4);

/// [time] on a local clock: `14:03:11`.
String _clock(DateTime time) {
  final local = time.toLocal();
  return [
    local.hour,
    local.minute,
    local.second,
  ].map((n) => '$n'.padLeft(2, '0')).join(':');
}
