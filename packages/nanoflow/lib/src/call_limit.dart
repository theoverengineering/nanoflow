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
// yet — it is going through the journal — holds back those called after it
// until it asks or ends: on resume, the copies started before, the first in
// the line, take the slots before the new ones.

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
  /// copies of the site run and none called before it waits.
  CallCopy copy(int limit) {
    final copy = CallCopy._(this, limit);
    _copies.add(copy);
    return copy;
  }

  /// Gives slots to the copies waiting, in the order they were called: up
  /// to the first that is not running and either has not asked yet or would
  /// run past its limit.
  void _fire() {
    for (final copy in _copies) {
      switch (copy._state) {
        case _CopyState.running:
          continue;
        case _CopyState.called:
          return;
        case _CopyState.waiting:
          if (_running >= copy.limit) return;
          _running++;
          copy._state = _CopyState.running;
          copy._slot!.complete();
      }
    }
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
}

/// A copy of a call with a limit: what an effect of it takes before it is
/// written, and what the run of the graph ends once the copy has ended.
final class CallCopy {
  CallCopy._(this._site, this.limit);

  final CallSite _site;

  /// How many copies of its site may run at once, this one counted.
  final int limit;

  var _state = _CopyState.called;

  /// Completed once the copy holds a slot; `null` until it asks for one.
  Completer<void>? _slot;

  /// Completes once the copy holds a slot of its site: asks for one the
  /// first time, and gives every effect of the copy the same wait after.
  Future<void> take() {
    if (_slot case final slot?) return slot.future;
    final slot = _slot = Completer<void>();
    _state = _CopyState.waiting;
    _site._fire();
    return slot.future;
  }

  /// The copy has ended: its slot, or its place in the line, goes to the
  /// copies after it.
  void end() {
    if (_state == _CopyState.running) _site._running--;
    _site._copies.remove(this);
    _site._fire();
  }
}
