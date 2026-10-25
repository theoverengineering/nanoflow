import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';

import 'codecs.dart';
import 'context.dart';
import 'errors.dart';
import 'exec.dart';
import 'graph.dart';
import 'owner.dart';
import 'project.dart';

/// Runs workflows: ordinary async functions of a [Flow] and an input, whose
/// effects are calls of [effect].
///
/// Every call of a workflow is a session: the library writes it to `runs/`
/// in the project [directory] as it goes — the input, every effect that runs
/// with its result, the workflow's result — so that [resume] can take a
/// session on after its process ended, taking the effects that finished from
/// its journal. Each session runs in a zone of its own, which gives each
/// effect a key that is the same on every run of the same code (spec §4.3);
/// several sessions of one flow may run at once.
///
/// The input, the result and every effect's result are kept as JSON (spec
/// §4.4): a value of a JSON type — `null`, a `bool`, a number, a `String`,
/// and lists and maps with `String` keys of them — as it is, a value of
/// another type through its `toJson`, which comes back through the
/// `fromJson` registered for its type with [addCodec]. A value that would
/// not come back is a [CodecException].
final class Flow {
  /// A flow whose sessions go to `runs/` in [directory]; by default the
  /// project directory: the directory of the binary in a compiled program;
  /// under `dart run`, which runs a snapshot in
  /// `.dart_tool/pub/bin/<package>/`, the directory of that package;
  /// otherwise the nearest ancestor of the script with a `pubspec.yaml`, or
  /// the script's directory when none has one.
  Flow({String? directory}) : directory = findProjectDir(directory: directory);

  /// The project directory: the graph file `nanoflow.graph.json` is read from
  /// it, and the sessions go to `runs/` in it.
  final String directory;

  late final FsStore _store = FsStore(
    runsDirOf(directory),
    owner: currentOwner(),
  );

  final _codecs = Codecs();

  /// The sessions that run in this process.
  final _sessions = <_Session>{};

  /// Whether [stop] was called.
  bool _stopped = false;

  /// Registers [fromJson] as the codec of [T]: a [T] that a session keeps —
  /// the input of a workflow, its result or the result of an effect — becomes
  /// JSON through its `toJson`, and [fromJson] makes a [T] of that JSON
  /// again, as [resume] needs.
  ///
  /// It serves `T?`, `List<T>`, `Map<String, T>` and any nesting of them
  /// too. A type of JSON needs no codec. A codec registered for [T] again
  /// takes the place of the one before.
  void addCodec<T>(T Function(Map<String, Object?> json) fromJson) =>
      _codecs.add(fromJson);

  /// Registers the enum whose values are [values] as a codec of [T]: a [T]
  /// that a session keeps is written as its name, and read back by it.
  ///
  /// It serves `T?`, `List<T>`, `Map<String, T>` and any nesting of them
  /// too, as [addCodec] does.
  void addEnum<T extends Enum>(List<T> values) => _codecs.addEnum(values);

  /// Starts a session of [workflow] with [input]: the session is written and
  /// owned by this process, and [workflow] runs.
  ///
  /// The session records the graph file as it is now and the hash of the
  /// code. Throws, having written nothing: an [ArgumentError] when
  /// [workflow] is not a top-level function or a static method, whose name
  /// names the session; a [CodecException] when [input] would not come back
  /// from JSON; a [FlowStoppedException] once the flow is stopped; a
  /// [StorageException] when the session cannot be written.
  Future<FlowSession<R>> start<I, R>(
    Future<R> Function(Flow f, I input) workflow,
    I input,
  ) => _start(workflow, input, const _Journal());

  /// [start], for a session whose effects in [journal] have run before.
  Future<FlowSession<R>> _start<I, R>(
    Future<R> Function(Flow f, I input) workflow,
    I input,
    _Journal journal,
  ) async {
    final name = workflowNameOf(workflow);
    final inputJson = _codecs.encode<I>(input);
    final graph = await graphSnapshotOf(directory);
    final package = await packageOf(directory, graph);
    final code = await runningCodeHashOf(directory);
    _checkNotStopped();
    final handle = await _stored(
      () => _store.createSession(
        workflow: name,
        graph: graph,
        input: (value: inputJson),
        code: code,
      ),
    );
    final session = _Session(this, handle, package, journal, graph);
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

  /// Takes on the session [sessionId] of [workflow] in this process (spec
  /// §4.6): it runs [workflow] again with the session's input, and every
  /// effect that finished before gives its saved result instead of running.
  ///
  /// An effect is taken from the journal when its key has an `effect-finished`
  /// there, the effect it followed then (`after`) is the one it follows now,
  /// and its saved result comes back from JSON as the type the code
  /// declares now (see [addCodec]); any other effect runs live, in the record
  /// of its key when the session has one. A saved result whose type has no
  /// codec now is not run again: the session ends there as on a failure of
  /// its store, with a [CodecException], and can be resumed once the codec
  /// is registered.
  ///
  /// Writes `session-resumed` with the hash of the code, and when that is
  /// not the code the session ran last and there is a graph file, the graph
  /// file as it is now.
  ///
  /// A session that has ended runs nothing, and nothing is written to it:
  /// the result is its saved result, or a [SessionFailedException] with its
  /// saved error and stack trace.
  ///
  /// The input and the saved result come back from JSON as the types the
  /// code declares (see [addCodec]); one that does not is a
  /// [CodecException]: for the result, the session's.
  ///
  /// Throws, having written no event: an [ArgumentError] when [workflow] is
  /// not a top-level function or a static method; a [FlowStoppedException]
  /// once the flow is stopped; a [SessionNotFoundException] when `runs/` has
  /// no session [sessionId]; a [SessionBusyException] when another process
  /// owns it, or this one runs it already; a [WorkflowMismatchException]
  /// when it is a session of another workflow; a [CodecException] when its
  /// saved input does not come back; a [StorageException] when it cannot be
  /// read.
  Future<FlowSession<R>> resume<I, R>(
    Future<R> Function(Flow f, I input) workflow,
    String sessionId,
  ) async {
    final name = workflowNameOf(workflow);
    _checkNotStopped();
    final handle =
        await _stored(() => _store.openSession(sessionId)) ??
        (throw SessionNotFoundException(sessionId));
    try {
      final session = handle.session;
      if (session.workflow != name) {
        throw WorkflowMismatchException(sessionId, session.workflow, name);
      }
      final events = await _stored(handle.events);
      final state = replaySession(events);
      if (state.status == SessionStatus.failed) {
        await handle.release();
        return FlowSession._(sessionId, _savedError<R>(sessionId, events));
      }
      if (state.status == SessionStatus.finished) {
        final outputId = state.outputId;
        final json = outputId == null
            ? null
            : await _stored(() => handle.documentValue(outputId));
        await handle.release();
        return FlowSession._(sessionId, _decoded<R>(json));
      }
      final inputId = session.inputId;
      final input = _codecs.decode<I>(
        inputId == null
            ? null
            : await _stored(() => handle.documentValue(inputId)),
      );
      final journal = await _journalOf(handle, state);
      final graph = await graphSnapshotOf(directory);
      final code = await runningCodeHashOf(directory);
      String? graphId;
      // Without a graph file there is no snapshot: the session has none
      // for this code, as `graph: null` says at its start.
      if (code != state.codes.lastOrNull && graph != null) {
        _checkNotStopped();
        graphId = await _stored(() => handle.writeDocument(graph));
      }
      _checkNotStopped();
      await _stored(
        () => handle.appendEvent(
          SessionResumed(time: systemClock(), code: code, graphId: graphId),
        ),
      );
      final running = _Session(
        this,
        handle,
        await packageOf(directory, graph),
        journal,
        graph,
      );
      return FlowSession._(sessionId, running.run(() => workflow(this, input)));
    } catch (_) {
      await handle.release();
      rethrow;
    }
  }

  /// The result of a session that finished with [json]: the [R] it stands
  /// for, or the [CodecException] when it does not decode to one.
  Future<R> _decoded<R>(Object? json) {
    try {
      return Future.value(_codecs.decode<R>(json));
    } on CodecException catch (e, s) {
      // Nobody can listen to it before [resume] gives it.
      return Future<R>.error(e, s)..ignore();
    }
  }

  /// The result of the session [sessionId], which failed: its saved error,
  /// from the last of its [events].
  Future<R> _savedError<R>(String sessionId, List<Event> events) {
    final failed = events.whereType<SessionFailed>().last;
    // Nobody can listen to it before [resume] gives it.
    return Future<R>.error(
      SessionFailedException(sessionId, failed.error),
      StackTrace.fromString(failed.stack),
    )..ignore();
  }

  /// What the journal of the session of [handle], [state] after replaying
  /// it, has of the effects.
  ///
  /// First writes to the `effect.json` of each effect that finished the
  /// `outputId` of its last `effect-finished` when it has another: the process
  /// died between the two (D3).
  Future<_Journal> _journalOf(SessionHandle handle, SessionState state) async {
    final outcomes = {
      for (final effect in state.effects) effect.effectId: effect,
    };
    final records = <String, Effect>{};
    final saved = <String, _Saved>{};
    for (var record in await _stored(handle.effects)) {
      // Only an effect that finished has one.
      if (outcomes[record.id]?.outputId case final outputId?) {
        if (record.outputId != outputId) {
          _checkNotStopped();
          record = await _stored(
            () => handle.setEffectOutput(record, outputId),
          );
        }
        saved[record.key] = (
          after: record.after,
          value: await _stored(() => handle.documentValue(outputId)),
        );
      }
      records[record.key] = record;
    }
    return _Journal(saved: saved, records: records);
  }

  /// The ids of the sessions of [workflow] that have not ended, newest
  /// first, whether a process runs them or not.
  ///
  /// Throws an [ArgumentError] when [workflow] is not a top-level function
  /// or a static method; a [StorageException] when `runs/` cannot be read.
  Future<List<String>> unfinished(Function workflow) async {
    final name = workflowNameOf(workflow);
    return _stored(() => _store.unfinishedSessions(name));
  }

  /// Stops the flow: no effect starts in its sessions any more — [effect]
  /// throws a [FlowStoppedException] — and nothing more is written to them, so
  /// each can be resumed; no session starts or resumes either.
  ///
  /// Every program that `exec` runs in the sessions is stopped, with every
  /// process it started, and none starts any more: `exec` throws a
  /// [FlowStoppedException]. An effect that runs goes on, and its outcome is
  /// not written: it throws a [FlowStoppedException] at the workflow. A
  /// session's result is a [FlowStoppedException] once its workflow and its
  /// effects have ended, and then the session is let go.
  void stop() {
    _stopped = true;
    for (final session in _sessions) {
      session._programs.stop(const FlowStoppedException());
    }
  }

  void _checkNotStopped() {
    if (_stopped) throw const FlowStoppedException();
  }

  /// Runs the effect [name] of the session this is called in: [body] runs, and
  /// what it returns is written to the session and returned.
  ///
  /// What [body] prints goes to the effect's log, and so does the stderr of
  /// the programs `exec` runs in it.
  ///
  /// When [body] throws, the effect fails: the exception is written, and
  /// thrown on into the workflow. A result that would not come back from
  /// JSON as a [T] fails the effect with a [CodecException] (see [addCodec]).
  ///
  /// Throws a [StateError] when called outside a session of this flow: from
  /// anywhere but the code of a workflow that [start], [run] or [resume]
  /// runs, or after its session has ended. Throws a [FlowStoppedException]
  /// once the flow is stopped, and what ended the session once it has
  /// ended early: the [StorageException] of a failure of its store, or the
  /// [CodecException] of a saved result whose type has no codec.
  Future<T> effect<T>(String name, FutureOr<T> Function() body) {
    final session = _sessionHere(name);
    final trace = StackTrace.current;
    return session.effect(
      name,
      body,
      codec: _codecs.of<T>(),
      place: () => placeOf(
        trace,
        projectDir: session._projectDir,
        package: session._package,
      ),
    );
  }

  /// The session of this flow the code that calls the effect [name] runs in.
  ///
  /// Throws a [StateError] when there is none.
  _Session _sessionHere(String name) {
    final session = Zone.current[this];
    if (session is! _Session) {
      throw StateError(
        'effect "$name" was called outside a session of this flow: call it '
        'from the code of a workflow that the flow runs',
      );
    }
    return session;
  }
}

/// Runs [node] of the graph named [graph] on [input] as an effect of the
/// session of [flow] this is called in (graph node objects design §3): named
/// after the node, at the place the graph file gives the node in that graph,
/// its result journaled with the codec of the node's output type.
///
/// Throws as [Flow.effect] does.
Future<Object?> nodeEffect(
  Flow flow,
  String graph,
  Node<Object?, Object?> node,
  Object? input,
) {
  final session = flow._sessionHere(node.name);
  return session.effect<Object?>(
    node.name,
    () => node.runWith(input),
    codec: node.outputCodec(flow._codecs),
    place: () => session.placeOfNode(graph, node.name),
  );
}

/// Starts a session of [workflow] as [Flow.start] does, as one whose effects of
/// the keys in [saved] have finished before, following the effect `after`,
/// with the result whose JSON is `value`: such an effect returns its result
/// when it follows that effect, and neither runs nor writes anything (spec
/// §4.6, an effect from the journal).
///
/// For tests of the keys under many timings, which would otherwise write a
/// journal for each.
Future<FlowSession<R>> startWithSaved<I, R>(
  Flow flow,
  Future<R> Function(Flow f, I input) workflow,
  I input,
  Map<String, ({String? after, Object? value})> saved,
) => flow._start(workflow, input, _Journal(saved: saved));

/// A session [Flow.start] or [Flow.resume] has started.
final class FlowSession<R> {
  FlowSession._(this.id, this.result);

  /// The id of the session.
  final String id;

  /// What the workflow returned, once its session is written to the end; or
  /// the exception it threw.
  ///
  /// A session that ended without being written to the end — its flow was
  /// stopped, its store failed, or an effect's saved result had a type without
  /// a codec — ends with the [FlowStoppedException], the [StorageException]
  /// or the [CodecException]; one that [Flow.resume] found failed, with a
  /// [SessionFailedException].
  final Future<R> result;
}

/// An effect that finished: the key of the effect it followed, and the JSON of
/// its result.
typedef _Saved = ({String? after, Object? value});

/// What a session's journal has of its effects, by key.
final class _Journal {
  const _Journal({this.saved = const {}, this.records = const {}});

  /// The effects that finished.
  final Map<String, _Saved> saved;

  /// The records of the effects.
  final Map<String, Effect> records;
}

/// A session that runs in this process.
final class _Session {
  _Session(this._flow, this._handle, this._package, this._journal, this._graph)
    : _projectDir = _flow.directory,
      _outside = Zone.current,
      _programs = ExecScope(Zone.current) {
    _zone = KeyedZone(zoneValues: {_flow: this, ..._programs.zoneValues});
  }

  final Flow _flow;
  final SessionHandle _handle;
  final String _projectDir;

  /// The package of the project, for the places of effects.
  final String? _package;

  /// What the session's journal had of its effects when it started.
  final _Journal _journal;

  /// The graph file as it was when the session started or resumed; `null`
  /// when there was none.
  final Map<String, Object?>? _graph;

  /// [_graph] read; `null` when there is none or it cannot be read.
  late final GraphFile? _graphFile = () {
    final graph = _graph;
    if (graph == null) return null;
    try {
      return GraphFile.fromJson(graph);
    } on FormatException {
      return null;
    }
  }();

  /// Where the effect of the node [node] of the graph [graph] is: the place of
  /// the effect node of that name in the body of the graph of that name in the
  /// graph file, the place of the graph; `null` when the file has none.
  String? placeOfNode(String graph, String node) {
    for (final function
        in _graphFile?.functions.values ?? const <GraphFunction>[]) {
      if (function.name != graph) continue;
      for (final effect in function.body.nodes.whereType<EffectNode>()) {
        if (effect.name == node) return effect.place;
      }
    }
    return null;
  }

  /// The zone the session was started from. The library's own work for the
  /// session — writing its effects and their logs, turning values into JSON
  /// and back, running programs for `exec` — runs there, not in the
  /// session's zone, so it schedules nothing that would change the keys of
  /// the effects.
  final Zone _outside;

  late final KeyedZone _zone;

  /// The programs `exec` runs in the session.
  final ExecScope _programs;

  /// One future for each effect that runs live, which completes when the effect
  /// has ended and its outcome is written.
  final _running = <Future<void>>{};

  /// What ended the session before its end: the [StorageException] of a
  /// failure of its store, or the [CodecException] of an effect whose saved
  /// result has a type without a codec; `null` while there is none.
  Exception? _failure;

  /// Whether the session has ended: its workflow returned or threw, and
  /// every effect it started has ended.
  bool _ended = false;

  /// Runs [workflow] in the session's zone; once it and every effect it
  /// started have ended, writes its result or its exception, then lets the
  /// session go.
  ///
  /// Writes nothing at the end once the flow is stopped or the session has
  /// failed as on a failure of its store: the result is then the
  /// [FlowStoppedException], or the session's failure.
  Future<R> run<R>(Future<R> Function() workflow) async {
    _flow._sessions.add(this);
    try {
      ({R value, Object? json})? returned;
      Object? error;
      StackTrace? stack;
      try {
        final value = await _zone.run(workflow);
        returned = (value: value, json: _flow._codecs.encode<R>(value));
      } catch (e, s) {
        error = e;
        stack = s;
      }
      await _settled();
      if (returned case (:final value, :final json)?) {
        final outputId = await _write(() => _handle.writeDocument(json));
        await _write(
          () => _handle.appendEvent(
            SessionFinished(time: systemClock(), outputId: outputId),
          ),
        );
        return value;
      }
      await _write(
        () => _handle.appendEvent(
          SessionFailed(
            time: systemClock(),
            error: _oneLine(error!),
            stack: '$stack',
          ),
        ),
      );
      Error.throwWithStackTrace(error!, stack!);
    } finally {
      _flow._sessions.remove(this);
      await _handle.release();
    }
  }

  /// Waits until no effect of the session runs, the effects they start
  /// included. Then the session has ended: no effect starts in it any more.
  Future<void> _settled() async {
    while (_running.isNotEmpty) {
      await Future.wait(_running.toList());
    }
    _ended = true;
  }

  /// Calls the effect [name] in the current context of the session's code;
  /// its result becomes JSON and comes back through [codec], and [place]
  /// gives where it is when a record of it is made.
  ///
  /// An effect that finished before following the same effect gives its result
  /// and writes nothing, when its result still comes back from JSON as a
  /// [T]; any other runs live.
  Future<T> effect<T>(
    String name,
    FutureOr<T> Function() body, {
    required TypeCodec codec,
    required String? Function() place,
  }) {
    _checkWritable();
    if (_ended) {
      throw StateError('effect "$name" was called after its session ended');
    }
    return _zone.effect(
      name,
      (effect) => _outside.run(() {
        final saved = _journal.saved[effect.key];
        if (saved != null && saved.after == effect.after) {
          try {
            return Future.value(codec.decode(saved.value) as T);
          } on CodecException catch (e) {
            if (!codec.canDecode) {
              // [T] has no codec: the code that resumes the session has not
              // registered it, and running the effect again would repeat
              // what it did. The session ends as on a failure of its store,
              // and can be resumed once the codec is there (spec §4.4).
              return Future<T>.error(_failed(e));
            }
            // The JSON does not decode to a [T]: not a result of this effect
            // as the code has it now, as one that followed another effect is
            // not. It runs again (spec §4.4).
          }
        }
        return _live(effect, body, codec, place);
      }),
    );
  }

  /// Runs [body] as [effect] and writes it: `effect-started`, then its result
  /// and `effect-finished`, or `effect-failed`. What the body prints goes to
  /// the effect's log, which is written before the effect's outcome.
  Future<T> _live<T>(
    KeyedEffect effect,
    FutureOr<T> Function() body,
    TypeCodec codec,
    String? Function() place,
  ) async {
    final ended = Completer<void>();
    _running.add(ended.future);
    try {
      final record = await _started(effect, place);
      final output = _EffectOutput(this, record.id);
      final T value;
      final Object? json;
      try {
        try {
          value = await effect.runBody(() => output.bodyZone().run(body));
        } finally {
          await output.close();
        }
        json = codec.encode(value);
      } catch (e, s) {
        await _write(
          () => _handle.appendEvent(
            EffectFailed(
              time: systemClock(),
              effectId: record.id,
              error: _oneLine(e),
              stack: '$s',
            ),
          ),
        );
        rethrow;
      }
      final outputId = await _write(() => _handle.writeDocument(json));
      await _write(
        () => _handle.appendEvent(
          EffectFinished(
            time: systemClock(),
            effectId: record.id,
            outputId: outputId,
          ),
        ),
      );
      await _write(() => _handle.setEffectOutput(record, outputId));
      return value;
    } finally {
      _running.remove(ended.future);
      ended.complete();
    }
  }

  /// Writes that [effect] starts: `effect-started` in the record of its key
  /// when the session has one (D2), otherwise in a new one at [place]; gives
  /// the record.
  Future<Effect> _started(KeyedEffect effect, String? Function() place) async {
    final known = _journal.records[effect.key];
    if (known == null) {
      final record = await _write(
        () => _handle.createEffect(
          name: effect.name,
          key: effect.key,
          after: effect.after,
          place: place(),
        ),
      );
      await _write(
        () => _handle.appendEvent(
          EffectStarted(time: systemClock(), effectId: record.id),
        ),
      );
      return record;
    }
    await _write(
      () => _handle.appendEvent(
        EffectStarted(time: systemClock(), effectId: known.id),
      ),
    );
    if (known.after == effect.after) return known;
    // A result the record is given from now on is for a call that follows
    // what this one follows. Only after `effect-started`, which voids the
    // result it has: until then, that result goes with the `after` it has.
    return _write(() => _handle.setEffectAfter(known, effect.after));
  }

  /// Does [write], a write to the session's store.
  ///
  /// Writes nothing, and throws a [FlowStoppedException], once the flow is
  /// stopped; writes nothing, and throws the session's failure, once it has
  /// one. A write that fails is that failure: the session is not written any
  /// more.
  Future<T> _write<T>(Future<T> Function() write) async {
    _checkWritable();
    try {
      return await _stored(write);
    } on StorageException catch (e) {
      throw _failed(e);
    }
  }

  /// The session has failed with [failure], as when its store fails: the
  /// session is not written any more, and its programs are stopped. Gives
  /// the session's failure, the first one.
  Exception _failed(Exception failure) {
    final first = _failure ??= failure;
    _programs.stop(first);
    return first;
  }

  void _checkWritable() {
    _flow._checkNotStopped();
    if (_failure case final failure?) throw failure;
  }
}

/// What [io], an operation of the store, gives; a failure of the store is a
/// [StorageException].
Future<T> _stored<T>(Future<T> Function() io) async {
  try {
    return await io();
  } on FileSystemException catch (e) {
    throw StorageException(e);
  } on StoreCorruptedException catch (e) {
    throw StorageException(e);
  } on FormatException catch (e) {
    throw StorageException(e);
  }
}

/// The text of [error] on one line: every run of line breaks is a space.
String _oneLine(Object error) => '$error'.replaceAll(RegExp(r'[\r\n]+'), ' ');

/// What the body of an effect outputs — the lines it prints and the stderr of
/// the programs `exec` runs in it — written to the effect's log, which is
/// opened at the first byte.
///
/// Takes nothing once the effect has ended, the flow is stopped or the store of
/// the session has failed — nothing more is written to the session then —
/// and the output goes to the process's own. A log that cannot be written is
/// a failure of the store.
final class _EffectOutput implements ProgramLog {
  _EffectOutput(this._session, this._effectId);

  final _Session _session;
  final String _effectId;

  /// The effect's log; `null` until the first output.
  EffectLog? _log;

  /// Whether the effect has ended.
  bool _closed = false;

  /// A zone for the body of the effect, forked from the current one, in
  /// which `print` and `exec` write to this output.
  Zone bodyZone() => Zone.current.fork(
    specification: ZoneSpecification(
      print: (self, parent, zone, line) {
        if (!add(utf8.encode('$line\n'))) parent.print(zone, line);
      },
    ),
    zoneValues: logZoneValues(this),
  );

  @override
  bool add(List<int> bytes) {
    if (_closed || _session._flow._stopped || _session._failure != null) {
      return false;
    }
    // Outside the session's zone: writing to the log schedules callbacks.
    _session._outside.run(() => (_log ??= _open()).add(bytes));
    return true;
  }

  /// Opens the effect's log, whose failure is the session's.
  ///
  /// The record of the effect was created or listed by the session's handle,
  /// which so knows its directory even when it is gone: the log then fails.
  EffectLog _open() {
    final log = _session._handle.openLog(_effectId);
    unawaited(log.failed.then((e) => _session._failed(StorageException(e))));
    return log;
  }

  @override
  int get unwritten => _log?.unwritten ?? 0;

  @override
  Future<void> flush() async => _log?.flush();

  /// Takes no more output, and writes what it took.
  Future<void> close() async {
    _closed = true;
    await _log?.close();
  }
}
