import 'dart:async';

import 'package:nanoflow_model/nanoflow_model.dart';

import 'processes.dart';

/// What became of the process of an owner that is watched.
enum _Fate {
  /// It exited.
  exited,

  /// Watching it failed: whether it runs cannot be known.
  unknown,
}

/// The owners of the sessions whose journal goes on, as their storage
/// records them, and whether their processes run: what `owner-changed` tells
/// (design §5). Each reader of a storage reads the records its own way —
/// `.owner.lock` of a session directory, a row of a database — and gives
/// them to [observe].
///
/// An owner is a pid and the time its process started. The exit of a new
/// owner's process is watched with [Processes.exitOf] before its start is
/// compared with [Processes.startOf]: a process that exits in between is
/// told gone all the same. An exit, or a watch that fails, is told on
/// [news], so that a scan looks again.
///
/// A scan [observe]s the owner of a session before it reads the session's
/// journal, and [tell]s what it observed after, only while the journal goes
/// on. An owner writes the last event of a session before it lets the
/// session go or its process exits: the journal read after the observation
/// holds that event, and a session that ended is never told without an
/// owner, or with one that is not alive.
final class Owners {
  Owners(this._processes);

  final Processes _processes;

  /// The sessions whose owner has been observed, by id.
  final Map<String, _Told> _sessions = {};

  final StreamController<void> _news = StreamController<void>();

  bool _closed = false;

  /// An event each time the process of an owner that is watched exits, or
  /// watching it fails.
  Stream<void> get news => _news.stream;

  /// The owner of the session [sessionId] now, as [record] has it, and
  /// whether it is alive: the `owner-changed` for [tell] to give once the
  /// session's journal has been read.
  ///
  /// An owner other than the one told last is watched. The one told last is
  /// not alive once its process has exited, and unknown once watching it
  /// failed.
  ///
  /// A [record] of `owner: null` says the session has no owner. A `null`
  /// record is one that is being written, its new owner over the old one:
  /// then it gives `null`, what was told stays, and the next scan reads it
  /// again.
  OwnerChanged? observe(String sessionId, ({Owner? owner})? record) {
    if (record == null) return null;
    final told = _sessions[sessionId] ??= _Told();
    final last = told.change;
    final owner = record.owner;
    final alive = last == null || owner != last.owner
        ? _watch(sessionId, told, owner)
        : switch (told.watch?.fate) {
            null => last.alive,
            _Fate.exited => false,
            _Fate.unknown => null,
          };
    return OwnerChanged(sessionId: sessionId, owner: owner, alive: alive);
  }

  /// Gives [observed], which [observe] gave before the session's journal was
  /// read, to [out] when it differs from what was told last of the session,
  /// or nothing was. A scan tells only while the session's journal goes on.
  void tell(OwnerChanged observed, EventSink<Change> out) {
    final told = _sessions[observed.sessionId];
    if (told == null || observed == told.change) return;
    told.change = observed;
    out.add(observed);
  }

  /// Forgets the owner of the session [sessionId] and stops telling its
  /// exit: the session's journal has ended.
  void drop(String sessionId) => _sessions.remove(sessionId);

  /// Forgets every owner: nothing heard from now on is told.
  void close() {
    _closed = true;
    _sessions.clear();
    unawaited(_news.close());
  }

  /// Watches the process of [owner], the new owner of the session
  /// [sessionId] that [told] is of, and tells whether it is alive: `false`
  /// for no owner, and `null`, without watching, for an owner without a
  /// start or when [_processes] cannot tell.
  bool? _watch(String sessionId, _Told told, Owner? owner) {
    told.watch = null;
    if (owner == null) return false;
    if (owner.started == null || !_processes.supported) return null;
    final watch = told.watch = _Watch();
    unawaited(
      Future.sync(() => _processes.exitOf(owner.pid)).then(
        (_) => _heard(sessionId, watch, _Fate.exited),
        onError: (Object _) => _heard(sessionId, watch, _Fate.unknown),
      ),
    );
    return Owner(pid: owner.pid, started: _processes.startOf(owner.pid)) ==
        owner;
  }

  /// Takes the [fate] of the process [watch] waits for, and tells [news] when
  /// that is still the process of the owner of the session [sessionId].
  void _heard(String sessionId, _Watch watch, _Fate fate) {
    watch.fate = fate;
    if (!_closed && _sessions[sessionId]?.watch == watch) _news.add(null);
  }
}

/// What has been told of the owner of a session.
final class _Told {
  /// The last `owner-changed` given; `null` before the first.
  OwnerChanged? change;

  /// The watch of the process of the owner told; `null` when it is not
  /// watched.
  _Watch? watch;
}

/// A wait for the exit of the process of an owner.
final class _Watch {
  /// What has become of the process; `null` while it runs.
  _Fate? fate;
}
