/// Step keys with no graph and no stack traces.
///
/// A workflow runs in a zone that gives every callback it schedules — above
/// all the one continuation the VM registers for each call of an async
/// function — a context of its own: the context it was scheduled in plus
/// its number there, `~3`. Code runs in one context at a time and in the
/// same order on every run, so the numbers are the same on every run,
/// whatever the timing; copies side by side get different ones even before
/// their first step. Right after `await <step>` — when a call is resumed
/// with that step's very result — the call takes the step's context
/// instead; after any other await it keeps its own, so after
/// `await Future.wait(copies)` the parent goes on in its own context,
/// whichever copy finished last. A step's key is its context plus its own
/// name and number there: `upload#2/verify#1`.
library;

import 'dart:async';

class Flow {
  Flow({this.journal = const {}});

  /// Saved results by key: what a run before the crash completed.
  final Map<String, Object?> journal;

  /// What this run completed, by key.
  final record = <String, Object?>{};

  List<String> _context = const [];
  final _counts = <String, int>{};
  final _scheduled = <String, int>{};

  /// The result a step is handing over right now, and the step's context.
  ({Object? value, List<String> key})? _delivering;

  /// Runs [body] as the step [name], or returns its saved result.
  Future<T> step<T>(String name, Future<T> Function() body) {
    final parent = _context.join('/');
    final n = _counts['$parent|$name'] = (_counts['$parent|$name'] ?? 0) + 1;
    final next = [..._context, '$name#$n'];
    final key = next.join('/');
    // Live or saved, the step schedules the same callbacks in the caller's
    // context, so the numbers after it do not change on a resume.
    final saved = journal.containsKey(key);
    final value =
        _with(
          next,
          saved ? () => Future<T>.value(journal[key] as T) : body,
        ).then((v) {
          if (!saved) record[key] = v;
          return v;
        });
    return _StepFuture(this, next, value);
  }

  /// A context for a callback scheduled now: the current one plus the
  /// callback's number in it.
  List<String> _child() {
    final parent = _context.join('/');
    final k = _scheduled[parent] = (_scheduled[parent] ?? 0) + 1;
    return [..._context, '~$k'];
  }

  /// Runs [workflow] in the zone that carries the contexts.
  Future<void> run(Future<void> Function(Flow f) workflow) {
    final spec = ZoneSpecification(
      scheduleMicrotask: (self, parent, zone, f) {
        final c = _child();
        parent.scheduleMicrotask(zone, () => _with(c, f));
      },
      createTimer: (self, parent, zone, duration, f) {
        final c = _child();
        return parent.createTimer(zone, duration, () => _with(c, f));
      },
      registerCallback: <R>(self, parent, zone, R Function() f) {
        final c = _child();
        return parent.registerCallback(zone, () => _with(c, f));
      },
      // The VM registers one continuation per call of an async function, at
      // its first await, and resumes every later await through it: the
      // context belongs to that call.
      registerUnaryCallback: <R, T>(self, parent, zone, R Function(T) f) {
        var context = _child();
        return parent.registerUnaryCallback(zone, (T a) {
          final d = _delivering;
          if (d != null && identical(d.value, a)) {
            // Resumed with a step's very result: right after `await <step>`.
            context = d.key;
            _delivering = null;
          }
          return _with(context, () => f(a));
        });
      },
      registerBinaryCallback:
          <R, T1, T2>(self, parent, zone, R Function(T1, T2) f) {
            final c = _child();
            return parent.registerBinaryCallback(
              zone,
              (T1 a, T2 b) => _with(c, () => f(a, b)),
            );
          },
    );
    return runZoned(() => workflow(this), zoneSpecification: spec);
  }

  R _deliver<R, T>(List<String> key, R Function(T) onValue, T value) =>
      _with(key, () {
        _delivering = (value: value, key: key);
        try {
          return onValue(value);
        } finally {
          _delivering = null;
        }
      });

  R _with<R>(List<String> context, R Function() f) {
    final saved = _context;
    _context = context;
    try {
      return f();
    } finally {
      _context = saved;
    }
  }
}

/// What [Flow.step] returns: `await` hands it the code that follows, which
/// the step resumes in its own context.
class _StepFuture<T> implements Future<T> {
  _StepFuture(this._flow, this._key, this._value);

  final Flow _flow;
  final List<String> _key;
  final Future<T> _value;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) => _value.then((v) => _flow._deliver(_key, onValue, v), onError: onError);

  @override
  Future<T> catchError(Function onError, {bool Function(Object)? test}) =>
      _value.catchError(onError, test: test);

  @override
  Future<T> whenComplete(FutureOr<void> Function() action) =>
      then((v) => v).whenComplete(action);

  @override
  Stream<T> asStream() => then((v) => v).asStream();

  @override
  Future<T> timeout(Duration limit, {FutureOr<T> Function()? onTimeout}) =>
      then((v) => v).timeout(limit, onTimeout: onTimeout);
}
