// The limit of a call (call limit design): a route that calls a node or a
// graph with `limit: n` runs at most n copies of that call at once. A copy is
// the run of what is called — the node's effect, or every effect of the
// graph's run —, and holds one slot from its first effect that runs live to
// its end. The copies of one call site — the node or the join whose route
// calls, and what it calls — in one run of a graph wait in one line, in the
// order they were called.
//
// A copy asks for its slot only when one of its effects is about to be
// written: an effect from the journal takes none, so a copy whose every
// effect is in the journal runs without one. A copy called and not asking
// yet holds back the new copies called after it until it asks or ends.
//
// On resume, the copies are called again in the order the replay makes
// them, which need not be the order they were called in before: the routes
// of several branches make copies of one call site as their nodes end. So a
// copy that ran before the process ended — one that replayed an effect from
// the journal, or whose first live effect has a record there — goes before
// the new ones, wherever it is in the line. And in a resumed session a new
// copy asks one turn of the event loop late: the replay runs in microtasks,
// so by then every copy it makes has been called, and every one that ran
// before has asked for its slot or ended.

import 'dart:async';
import 'dart:collection';

/// The copies of one call site in one run of a graph, in the order they
/// were called.
final class CallSite {
  /// The copies that have not ended, in the order they were called.
  final _copies = LinkedHashSet<CallCopy>.identity();

  /// How many of [_copies] hold a slot.
  int _running = 0;

  /// A copy of the call, called now, which runs once fewer than [limit]
  /// copies of the site run and none it must let go first waits.
  CallCopy copy(int limit) {
    final copy = CallCopy._(this, limit);
    _copies.add(copy);
    return copy;
  }

  /// Gives slots to the copies waiting: first to those that ran before the
  /// process ended, in the order they were called, then to the new ones, in
  /// that order up to the first that has not asked yet; each while fewer
  /// copies run than its limit, the first that would run past it stopping
  /// all after it.
  void _fire() {
    for (final copy in _copies) {
      if (copy._state != _CopyState.waiting || !copy._resumed) continue;
      if (_running >= copy.limit) return;
      _grant(copy);
    }
    for (final copy in _copies) {
      switch (copy._state) {
        // An ended copy is out of the line.
        case _CopyState.running || _CopyState.ended:
          continue;
        case _CopyState.called:
          return;
        case _CopyState.waiting:
          if (_running >= copy.limit) return;
          _grant(copy);
      }
    }
  }

  void _grant(CallCopy copy) {
    _running++;
    copy._state = _CopyState.running;
    copy._slot!.complete();
  }
}

/// Where a copy of a call is.
enum _CopyState {
  /// Called; none of its effects has asked for a slot yet.
  called,

  /// One of its effects has asked for a slot; none is free yet.
  waiting,

  /// It holds a slot.
  running,

  /// It has ended: its slot, or its place in the line, is given up.
  ended,
}

/// A copy of a call with a limit: what an effect of it takes before it is
/// written, and what the run of the graph ends once the copy has ended.
final class CallCopy {
  CallCopy._(this._site, this.limit);

  final CallSite _site;

  /// How many copies of its site may run at once, this one counted.
  final int limit;

  var _state = _CopyState.called;

  /// Whether the copy ran before the process ended: it replayed an effect
  /// from the journal, or an effect of it that has a record there asked for
  /// its slot.
  var _resumed = false;

  /// Completed once the copy holds a slot; `null` until it asks for one.
  Completer<void>? _slot;

  /// An effect of the copy came from the journal: the copy ran before.
  void replayed() => _ranBefore();

  /// Completes once the copy holds a slot of its site: asks for one the
  /// first time, and gives every effect of the copy the same wait after.
  ///
  /// [started] says that the effect asking has a record in the journal: the
  /// copy ran before. In a session [resuming], a copy not known to have run
  /// before asks one turn of the event loop late, once the replay has made
  /// and started the copies that did; found to have run before in the
  /// meantime, it asks at once.
  ///
  /// Throws a [StateError] once the copy has ended; the wait fails with one
  /// when the copy ends before it got a slot.
  Future<void> take({bool started = false, bool resuming = false}) {
    _checkNotEnded('take a slot');
    if (started) _ranBefore();
    if (_slot case final slot?) return slot.future;
    final slot = _slot = Completer<void>();
    if (resuming && !_resumed) {
      Timer.run(_ask);
    } else {
      _ask();
    }
    return slot.future;
  }

  /// The copy ran before the process ended: it goes before the new copies,
  /// and asks now when it was to ask late.
  void _ranBefore() {
    _resumed = true;
    if (_slot != null && _state == _CopyState.called) _ask();
  }

  /// Asks for a slot: waits in the line of the site. Once only: a late ask
  /// after the copy has asked, got its slot or ended does nothing.
  void _ask() {
    if (_state != _CopyState.called) return;
    _state = _CopyState.waiting;
    _site._fire();
  }

  /// The copy has ended: its slot, or its place in the line, goes to the
  /// copies after it.
  ///
  /// Throws a [StateError] when it has ended already.
  void end() {
    _checkNotEnded('end');
    if (_state == _CopyState.running) _site._running--;
    // What still waits for a slot would wait for ever: the copy has none to
    // get. (A graph's run ends a copy only once its effects have ended.)
    if (_slot case final slot? when !slot.isCompleted) {
      slot.completeError(
        StateError('a copy of a call ended before it got a slot'),
      );
    }
    _state = _CopyState.ended;
    _site._copies.remove(this);
    _site._fire();
  }

  void _checkNotEnded(String what) {
    if (_state == _CopyState.ended) {
      throw StateError('a copy of a call cannot $what once it has ended');
    }
  }
}
