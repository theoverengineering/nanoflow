// Step keys (spec §4.3, decision D1), ported from
// prototypes/step_keys/lib/flow.dart.
//
// A session's code runs in a zone that gives every callback the code
// registers — above all the one continuation the VM registers for each call
// of an async function, at its first await — a context of its own: the
// context it was registered in plus its number among the callbacks of its
// kind registered there. Right after `await <step>` — when a call is resumed
// with that step's very result — the call takes the step's context instead;
// after any other await it keeps its own, so after `await Future.wait(copies)`
// the parent goes on in its own context, whichever copy finished last. A
// step's key is its name, its number among the steps of that name in the
// context it is called in, and the hash of that context: `upload#2@<h>`.
//
// Callbacks of two kinds are numbered apart. Those with an argument — the
// continuations of async functions, `then`, the listeners of streams — are
// `~k`; those without — timers and microtasks the code makes, as
// `Future.delayed` and `scheduleMicrotask` make them — are `~tk`. A
// microtask or a timer as such takes no number: it runs in the context it was
// scheduled in, and what it calls back was registered, and numbered, when it
// was made. So neither the microtask the VM schedules to resume an await of a
// future that is done already, nor the registration the root zone makes of a
// microtask or a timer this zone hands it to schedule, takes a number.
//
// What that guarantees: a step's key is the same on every run when, in each
// context on its way, the sequence of continuations and `then` callbacks
// registered there before it does not depend on the timing. Code runs one
// piece at a time in each context, so awaits, `Future.wait`, loops and
// `await for` register them in the order the code runs, and copies side by
// side get different numbers even before their first step. A timer's or a
// microtask's number is steady only where the sequence of timers and
// microtasks made in its context is: dart:async makes microtasks of its own
// for a stream when items wait in it, which depends on the timing. Numbered
// apart, they do not move the continuations around them, but they can move a
// timer made in the same context, and with it the key of a step that the
// timer's callback calls directly, as `Future.delayed(d, () => publish(f))`
// in the body of an `await for` does.
//
// Unlike the prototype, a step's body runs in a context of its own, `~0` of
// the step's, and not in the step's context itself, which is the context of
// the code that takes the step's result. A body that runs and one that does
// not, its result coming from the journal, then leave the numbers there the
// same: in the prototype the numbers in a step's context counted the
// callbacks of its body too, and after a resume the steps that followed a
// call there moved to other keys and ran again.
//
// And a step hands its result over in a future of the zone the session's zone
// was forked from, whatever gave it: a live step's result comes from there,
// and a saved one then behaves the same in every respect, the zone in which a
// late listener's microtask runs included.

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// `h(s)`: the first 16 hex digits of the sha256 of [s] in UTF-8.
String contextHash(String s) =>
    sha256.convert(utf8.encode(s)).toString().substring(0, 16);

/// A zone that gives every step called in it a key that is the same on every
/// run of the same code: one per session.
///
/// Code runs in it through [run]; [step] keys a step and hands its result to
/// the code that awaits it in the step's context.
final class KeyedZone {
  /// A zone forked from the current one, with [zoneValues].
  KeyedZone({Map<Object?, Object?>? zoneValues}) : _parent = Zone.current {
    _zone = _parent.fork(
      specification: _specification(),
      zoneValues: zoneValues,
    );
  }

  /// The zone this one was forked from: the futures of steps belong to it.
  final Zone _parent;

  late final Zone _zone;

  final _root = _Context.root();

  /// The context the code that runs now runs in. Between callbacks, when
  /// only code from outside the zone runs, it is the root, which no code of
  /// the session runs in after its first synchronous part.
  late _Context _current = _root;

  /// The result a step is handing over right now, and the step's context.
  ({Object? value, _Context context})? _delivering;

  /// Whether the zone is handing a microtask or a timer to the zone it was
  /// forked from, which registers the callback back in this zone.
  bool _scheduling = false;

  /// Runs [body] in the zone, in the root context.
  R run<R>(R Function() body) => _zone.run(() => _with(_root, body));

  /// Calls the step [name] in the current context and returns what [start]
  /// gives for it, in a future that resumes the code awaiting it in the
  /// step's context.
  ///
  /// [start] is called at once, in the step's own context, with the step's
  /// key: it gives the step's result, saved or from [KeyedStep.runBody]. The
  /// code that calls the step registers the same callbacks either way, and
  /// the result is handed over in a future of the zone this one was forked
  /// from.
  Future<T> step<T>(String name, Future<T> Function(KeyedStep step) start) {
    final caller = _current;
    final key = '$name#${caller.nextStep(name)}@${contextHash(caller.id)}';
    // One context for every code that takes the step's result: what takes
    // it twice goes on numbering where it was.
    final context = _Context.ofStep(key);
    // The body's own context. A step called in the body follows this step:
    // its `after` is this step's key.
    final own = _Context.child(context, '~0');
    final value = _with(own, () {
      final result = start(KeyedStep._(this, own, name, key, caller.after));
      return _parent.run(() => result.then((v) => v));
    });
    return _StepFuture(this, context, value);
  }

  ZoneSpecification _specification() => ZoneSpecification(
    // A microtask or a timer runs in the context it was scheduled in, and
    // takes no number there.
    scheduleMicrotask: (self, parent, zone, f) {
      final c = _current;
      _unnumbered(() => parent.scheduleMicrotask(zone, () => _with(c, f)));
    },
    createTimer: (self, parent, zone, duration, f) {
      final c = _current;
      return _unnumbered(
        () => parent.createTimer(zone, duration, () => _with(c, f)),
      );
    },
    // A callback without an argument: the callback of a timer or of a
    // microtask the code makes.
    registerCallback: <R>(self, parent, zone, R Function() f) {
      if (_scheduling) return parent.registerCallback(zone, f);
      final c = _current.timed();
      return parent.registerCallback(zone, () => _with(c, f));
    },
    // The VM registers one continuation per call of an async function, at its
    // first await, and resumes every later await through it: the context
    // belongs to that call.
    registerUnaryCallback: <R, T>(self, parent, zone, R Function(T) f) {
      var context = _current.child();
      return parent.registerUnaryCallback(zone, (T a) {
        final d = _delivering;
        if (d != null && identical(d.value, a)) {
          // Resumed with a step's very result: right after `await <step>`.
          context = d.context;
          _delivering = null;
        }
        return _with(context, () => f(a));
      });
    },
    registerBinaryCallback:
        <R, T1, T2>(self, parent, zone, R Function(T1, T2) f) {
          final c = _current.child();
          return parent.registerBinaryCallback(
            zone,
            (T1 a, T2 b) => _with(c, () => f(a, b)),
          );
        },
  );

  /// Runs [schedule], which hands a microtask or a timer to the zone this one
  /// was forked from. The root zone registers the callback it is handed in
  /// the zone it schedules it for, this one: that registration takes no
  /// number.
  T _unnumbered<T>(T Function() schedule) {
    final was = _scheduling;
    _scheduling = true;
    try {
      return schedule();
    } finally {
      _scheduling = was;
    }
  }

  R _deliver<R, T>(_Context context, R Function(T) onValue, T value) =>
      _with(context, () {
        _delivering = (value: value, context: context);
        try {
          return onValue(value);
        } finally {
          _delivering = null;
        }
      });

  R _with<R>(_Context context, R Function() f) {
    final saved = _current;
    _current = context;
    try {
      return f();
    } finally {
      _current = saved;
    }
  }
}

/// A step called in a [KeyedZone], as [KeyedZone.step] gives it to the code
/// that runs it.
final class KeyedStep {
  KeyedStep._(this._zone, this._own, this.name, this.key, this.after);

  final KeyedZone _zone;

  /// The step's own context, which its body runs in.
  final _Context _own;

  /// The name the step was called with.
  final String name;

  /// The key that finds the step's result again: `name#n@<h(context)>`.
  final String key;

  /// The key of the step whose result the context the step was called in
  /// took last; `null` when it took none.
  final String? after;

  /// Runs [body] in the zone, in the step's own context, from wherever it is
  /// called.
  R runBody<R>(R Function() body) =>
      _zone._zone.run(() => _zone._with(_own, body));
}

/// Where code runs, as far as step keys go.
final class _Context {
  _Context._(this._id, this._parent, this._label, this.after);

  /// The root of a session: `""`.
  _Context.root() : this._('', null, '', null);

  /// The context of the step [key]: the one the code that takes the step's
  /// result goes on in.
  _Context.ofStep(String key) : this._(key, null, '', key);

  /// The context [label] in [parent]: `~k` for the callback with an argument
  /// numbered k there, `~tk` for the one without, `~0` for a step's body.
  _Context.child(_Context parent, String label)
    : this._(null, parent, label, parent.after);

  /// The context's name, `null` until it is needed: it is a hash, and most
  /// callbacks never call a step.
  String? _id;

  /// The context this one was registered in, until [_id] is known.
  _Context? _parent;

  /// What tells this context from the others in its parent: `~3`, `~t2`.
  final String _label;

  /// The key of the step whose result this context took last; `null` when
  /// none. A callback gets the one of the context it was registered in.
  final String? after;

  /// How many callbacks with an argument were registered in this context so
  /// far.
  int _registered = 0;

  /// How many callbacks without an argument were registered in this context
  /// so far.
  int _timed = 0;

  /// How many steps of each name were called in this context so far.
  Map<String, int>? _steps;

  /// `""` for the root, the key for a step's context, and for a callback's
  /// `h(parent + "/" + label)`: the hash of the name of the context it was
  /// registered in and its label there, `~k` or `~tk`.
  String get id {
    if (_id case final id?) return id;
    // Computed from the nearest context whose name is known down, without a
    // call per level: a chain of callbacks can be long.
    final unnamed = <_Context>[];
    for (_Context? c = this; c != null && c._id == null; c = c._parent) {
      unnamed.add(c);
    }
    for (final c in unnamed.reversed) {
      c._id = contextHash('${c._parent!.id}/${c._label}');
      c._parent = null;
    }
    return _id!;
  }

  /// A context for a callback with an argument registered in this one now.
  _Context child() => _Context.child(this, '~${++_registered}');

  /// A context for a callback without an argument registered in this one
  /// now.
  _Context timed() => _Context.child(this, '~t${++_timed}');

  /// The number of a step of [name] called in this context now, from 1.
  int nextStep(String name) {
    final steps = _steps ??= {};
    return steps[name] = (steps[name] ?? 0) + 1;
  }
}

/// What [KeyedZone.step] returns: `await` hands it the code that follows,
/// which the step resumes in its own context.
final class _StepFuture<T> implements Future<T> {
  _StepFuture(this._zone, this._context, this._value);

  final KeyedZone _zone;
  final _Context _context;
  final Future<T> _value;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(T value) onValue, {
    Function? onError,
  }) => _value.then(
    (v) => _zone._deliver(_context, onValue, v),
    onError: onError,
  );

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
