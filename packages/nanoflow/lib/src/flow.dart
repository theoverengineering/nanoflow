import 'dart:async';
import 'dart:convert';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';

import 'context.dart';
import 'errors.dart';
import 'project.dart';

/// Runs workflows: ordinary async functions of a [Flow] and an input, whose
/// steps are calls of [step].
///
/// Every call of a workflow is a session: the library writes it to `runs/`
/// in the project [directory] as it goes — the input, every step that runs
/// with its result, the workflow's result — so that a session can go on
/// after the process ended, taking the steps that finished from its journal.
/// Each session runs in a zone of its own, which gives each step a key that
/// is the same on every run of the same code (spec §4.3); several sessions
/// of one flow may run at once.
///
/// The input, the result and every step's result must be JSON: `null`, a
/// `bool`, a number, a `String`, and lists and maps with `String` keys of
/// them; anything else is a [CodecException].
final class Flow {
  /// A flow whose sessions go to `runs/` in [directory]; by default the
  /// project directory: the directory of the binary in a compiled program,
  /// otherwise the nearest ancestor of the script with a `pubspec.yaml`, or
  /// the script's directory when none has one.
  Flow({String? directory}) : directory = findProjectDir(directory: directory);

  /// The project directory: the graph file `nanoflow.graph.json` is read from
  /// it, and the sessions go to `runs/` in it.
  final String directory;

  late final FsStore _store = FsStore(runsDirOf(directory));

  /// Starts a session of [workflow] with [input]: the session is written and
  /// owned by this process, and [workflow] runs.
  ///
  /// The session records the graph file as it is now and the hash of the
  /// code. Throws an [ArgumentError], having written nothing, when
  /// [workflow] is not a top-level function or a static method, whose name
  /// names the session; a [CodecException] when [input] is not JSON.
  Future<FlowSession<R>> start<I, R>(
    Future<R> Function(Flow f, I input) workflow,
    I input,
  ) async {
    final name = workflowNameOf(workflow);
    _checkJson<I>(input);
    final graph = await graphSnapshotOf(directory);
    final package = await packageOf(directory, graph);
    final handle = await _store.createSession(
      workflow: name,
      graph: graph,
      input: (value: input),
      code: await codeHashOf(directory),
    );
    final session = _Session(this, handle, package);
    return FlowSession._(
      handle.session.id,
      session.run(() => workflow(this, input)),
    );
  }

  /// Runs a session of [workflow] with [input] to its end: [start], then the
  /// session's [FlowSession.result].
  Future<R> run<I, R>(
    Future<R> Function(Flow f, I input) workflow,
    I input,
  ) async => (await start(workflow, input)).result;

  /// Runs the step [name] of the session this is called in: [body] runs, and
  /// what it returns is written to the session and returned.
  ///
  /// When [body] throws, the step fails: the exception is written, and
  /// thrown on into the workflow. A result that is not JSON fails the step
  /// with a [CodecException].
  ///
  /// Throws a [StateError] when called outside a session of this flow: from
  /// anywhere but the code of a workflow that [start] or [run] runs.
  Future<T> step<T>(String name, FutureOr<T> Function() body) {
    final session = Zone.current[this];
    if (session is! _Session) {
      throw StateError(
        'step "$name" was called outside a session of this flow: call it '
        'from the code of a workflow that the flow runs',
      );
    }
    return session.step(name, body, StackTrace.current);
  }
}

/// A session [Flow.start] has started.
final class FlowSession<R> {
  FlowSession._(this.id, this.result);

  /// The id of the session.
  final String id;

  /// What the workflow returned, once its session is written to the end; or
  /// the exception it threw.
  final Future<R> result;
}

/// A session that runs in this process.
final class _Session {
  _Session(Flow flow, this._handle, this._package)
    : _projectDir = flow.directory,
      _outside = Zone.current {
    _zone = KeyedZone(zoneValues: {flow: this});
  }

  final SessionHandle _handle;
  final String _projectDir;

  /// The package of the project, for the places of steps.
  final String? _package;

  /// The zone the session was started from. The library's own work for the
  /// session — writing its steps — runs there, not in the session's zone,
  /// so it schedules nothing that would change the keys of the steps.
  final Zone _outside;

  late final KeyedZone _zone;

  /// Runs [workflow] in the session's zone; writes its result or its
  /// exception, then lets the session go.
  Future<R> run<R>(Future<R> Function() workflow) async {
    try {
      final R result;
      try {
        result = await _zone.run(workflow);
        _checkJson<R>(result);
      } catch (e, s) {
        await _handle.appendEvent(
          SessionFailed(time: systemClock(), error: _oneLine(e), stack: '$s'),
        );
        rethrow;
      }
      final outputId = await _handle.writeDocument(result);
      await _handle.appendEvent(
        SessionFinished(time: systemClock(), outputId: outputId),
      );
      return result;
    } finally {
      await _handle.release();
    }
  }

  /// Calls the step [name] in the current context of the session's code;
  /// [trace] is the stack of the call.
  Future<T> step<T>(
    String name,
    FutureOr<T> Function() body,
    StackTrace trace,
  ) => _zone.step(name, (step) => _outside.run(() => _live(step, body, trace)));

  /// Runs [body] as [step] and writes it: the step's record, `step-started`,
  /// then its result and `step-finished`, or `step-failed`.
  Future<T> _live<T>(
    KeyedStep step,
    FutureOr<T> Function() body,
    StackTrace trace,
  ) async {
    final record = await _handle.createStep(
      name: step.name,
      key: step.key,
      after: step.after,
      place: placeOf(trace, projectDir: _projectDir, package: _package),
    );
    await _handle.appendEvent(
      StepStarted(time: systemClock(), stepId: record.id),
    );
    final T value;
    try {
      value = await step.runBody(body);
      _checkJson<T>(value);
    } catch (e, s) {
      await _handle.appendEvent(
        StepFailed(
          time: systemClock(),
          stepId: record.id,
          error: _oneLine(e),
          stack: '$s',
        ),
      );
      rethrow;
    }
    final outputId = await _handle.writeDocument(value);
    await _handle.appendEvent(
      StepFinished(time: systemClock(), stepId: record.id, outputId: outputId),
    );
    await _handle.setStepOutput(record, outputId);
    return value;
  }
}

/// The text of [error] on one line: every run of line breaks is a space.
String _oneLine(Object error) => '$error'.replaceAll(RegExp(r'[\r\n]+'), ' ');

/// Throws a [CodecException] for [T] unless [value] is JSON as it is,
/// without a `toJson`.
void _checkJson<T>(Object? value) {
  try {
    jsonEncode(value, toEncodable: (_) => throw const _NotJson());
  } on JsonCyclicError {
    throw CodecException(T, 'a list or a map contains itself');
  } on JsonUnsupportedObjectError catch (e) {
    throw CodecException(T, switch (e.unsupportedObject) {
      final num number => '$number is not a JSON number',
      Map() => 'a map with keys that are not strings is not JSON',
      final other => 'a ${other.runtimeType} is not a JSON value',
    });
  }
}

/// What the check for JSON throws for a value that is not.
final class _NotJson {
  const _NotJson();
}
