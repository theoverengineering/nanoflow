/// Which forks of the level drawn a session's code went through, and which
/// edges it took (effects design §5), read from the journal alone. No
/// condition is evaluated. Pure. The rules are stated in full here; the
/// design, the spec and the READMEs restate them for their readers.
///
/// Under the rule that every side effect is in an effect, the code between
/// two effects goes one way, set by what the effects gave. An effect's
/// `after` names the last effect whose result the context it was called in
/// took (spec §4.3). After an awaited call, a closure called in place or a
/// `Future.wait`, the context goes on with the `after` it had — unless what
/// it awaited handed it an effect's very result, as `return f.effect(…)`
/// does —, so the effect after them follows the effect before them, as their
/// first effects do. The effects of a session are a tree: each below the one
/// it follows.
///
/// **Where an effect is.** On the level at the nodes it is on or in, as for
/// the marks (spec §9 «Эффекты на графе»), or outside it. An effect not on
/// the graph at all — without a place, or at no node — is passed over: the
/// predecessor of an effect is the effect on the graph its `after` leads
/// back to, and the tree is of the effects on the graph.
///
/// **The ends before an effect.** The code before an effect E ended at the
/// effects below E's predecessor — below what E is below when it has none —
/// that no effect on the graph follows, that had finished by E's first
/// `effect-started`, and that lead to E on the level or are in one call
/// node with it: a wait ends after all it waits for, a call after all it
/// ran, while effects side by side start before either ends. They were
/// joined before E; E itself never is. An end joined before an effect that
/// started before E and had finished by then was passed: the code went on
/// from it to that effect, and it is not joined before E — `await
/// Future.wait([a(), b()]); if (c) await Future.wait([x(), y()]); await z();`
/// joins a and b before x and y, and x and y, not a and b, before z.
///
/// **Transitions** are what the code did between an effect E on the graph
/// and the code before it, along the level's edges. A transition goes:
///
/// - from the ends before E, when there are some — not from one in one call
///   node with E: from it the code went to E inside;
/// - else from the body's start to E when its predecessor is outside the
///   level, or there is none — no `after`, or one no record has;
/// - else from the predecessor to E when both are on the level, unless they
///   are in one call node: then it is inside it;
/// - but on the body of a function the workflow calls, when no way leads
///   from the predecessor to E in it, from the predecessor to the body's end
///   and from the body's start to E, a run of its own: the code left the
///   body and came into it again, as two calls of the function one after
///   the other with no effect between them do — only when both ways are
///   there;
/// - from the predecessor to the body's end when E is outside the level;
/// - and, once the session has finished, from each effect on the level that
///   no effect on the graph follows, and that was not joined before one — or
///   only before effects that started in its own millisecond, as ends side
///   by side in one wait are —, to the body's end.
/// What lies on every simple path of a transition through forks and calls
/// was passed, and its edges taken. On the body of a function the workflow
/// calls, of a transition between two effects that could also have gone out
/// of the body after the one and into it again before the other, only what
/// lies on every path of both: the code may have left between them.
///
/// Some transitions mark nothing, though the code may have gone their way:
/// those through an effect not on the graph — from an end it follows, or to
/// an effect that follows it —, where the code went is not drawn; those from
/// an end joined only before effects that started in its millisecond, as it
/// may have run beside them; those to an effect whose ends were all passed,
/// as they may have been passed by effects beside it — two calls of a
/// function one after the other leave the journal `Future.wait([x(),
/// helper()])` leaves when helper's first effect comes after x ended —; and
/// those to an effect whose ends are all in one call node with it, as
/// effects side by side there that end in the millisecond they start join
/// each other so.
///
/// **Failure routes.** A node with a failure route (edges `failed`,
/// failure route design) chooses its way out as a fork does: a transition
/// from an effect on an effect node that has such edges leaves by them when
/// the effect failed, by the others when it finished. A call's outcome is
/// not in the journal — a failure in it may have been caught inside —, so
/// a transition from a call leaves by any of its edges. Once a transition
/// went out of a node with a failure route, the node is passed as a fork is
/// for what is darker: its exits on none of the ways the code may have gone
/// are darker.
///
/// **Runs.** The transitions of one run of the code are one pass of the
/// forks on them: those from one predecessor; those from the body's start
/// again after one predecessor; those to the effects after one wait, from all
/// it joined; and those to the body's end from the effects one run came to.
/// Each transition from the body's start to an effect whose predecessor is
/// not on the level is a run of its own — each call comes into the body
/// so —, but on the workflow's own body, which the code comes into once,
/// those of effects with the same `after` are one. The count is of the runs
/// the journal tells apart: with waits and calls it can differ from how
/// many times the condition was evaluated.
///
/// **The ways the code may have gone** mark nothing, but no exit on them is
/// darker ([_mayHaveGone]): the walks of every transition, marking or not; on
/// the body of a function the workflow calls, out of the body and into it again
/// between the two ends of each transition, and between each effect and its
/// predecessor; while the session has not finished — it runs, failed or was cut
/// off —, from each effect that has finished, that no effect on the graph
/// follows and that was not joined before one (but for effects that started in
/// its millisecond), to anywhere: the code may have gone on from it before it
/// stopped — from one that runs, it has not —, and on the body of a function
/// the workflow calls from the body's start too, since a call may have begun;
/// and the other branches of a `Future.wait` beside an edge of a fork on any of
/// them.
///
/// **Darker exits.** An exit of a passed fork on none of those ways. On the
/// body of a function the workflow calls, only when no effect node of it
/// holds more than one of the effects shown: otherwise the function may have
/// run more than once, and the ends of an earlier call can read as joined
/// before an effect of a later one, the way out of the body that call took
/// lost. The gate is needed, not enough (below).
///
/// **Limits** — what the journal does not tell, and the marks it leaves
/// wrong:
///
/// - *Effects side by side read as a wait*: false taken edges, false
///   passes, and darker exits the code took. An effect that finished before
///   another below the same started — earlier, or in the same millisecond,
///   as fast effects do — though the code did not wait for it, and that
///   leads to it on the level, reads as joined before it: round a loop; into
///   a call node of a function called again after the wait; or from a call
///   node of a function drawn more than once, where the effect is on each.
///   The library's `await Future.wait([e0(), e1()]); if (mode == 'deep') {
///   await quickSub(); if (mode.length > 3) await g(); } await
///   Future.wait([quickSub(), e4()]);`, quickSub one fast effect, mode
///   `flat`, can show `mode.length > 3` passed: the wait's quickSub, ended in
///   the millisecond e4 started, reads as the deep branch's, joined before
///   e4. Fast effects side by side in a loop that read as joined round it
///   pass each other, and take the place of the way into the loop: `await
///   (() async { await Future.wait([e0(), e1(), e2()]); })(); while (i < 1) {
///   await Future.wait([e3(), e4()]); i++; } await e5();` can darken the
///   loop's way out to e5, which the code took.
/// - *The ends of an earlier call*, on the body of a function run more than
///   once, read as joined before an effect of a later call: false taken
///   edges; rarely a false pass — `helper` above with a slow `sub` in place
///   of quickSub, called twice with mode `flat`, shows `mode.length > 3`
///   passed —; and darker exits an earlier call took, where its waits or
///   closures ran on different effect nodes, each holding one effect: two
///   calls, one after the other or side by side, of `if (c) await
///   Future.wait([x(), y()]); else await Future.wait([u(), v()]); if (k)
///   await z();` darken `k>`, which the first took, as `await (() async { if
///   (!first) { await e4(); await e5(); } else { await e6(); } })(); if
///   (!first) await e7();`, first true then false, darkens the way out the
///   first took.
/// - *Effects side by side that end in the millisecond they start*, in one
///   call node or leading to each other round a loop: each reads as
///   joined before the other, and so, the other done, as passed. The effect
///   after them that has no other end
///   finds all its ends passed: it marks nothing, and the way the code took
///   to it can be darker, in a finished session too. The library's `h66 {
///   await e3(); await e4(); await Future.wait([e5(), e6()]); }`, called in a
///   closure and then again, followed by `while (i < 1) { await e1(); await
///   e2(); i++; }`, can darken the loop's way to e1 when e5 and e6 end in the
///   millisecond they start.
/// - *Counts* (see «Runs»): they can be lower or higher than how many times
///   the condition was evaluated. An effect whose ends are all in one call
///   node with it comes by a way that marks nothing, and its way to the end
///   is of the run it came by, not of the wait's: that too moves counts,
///   either way.
/// - *Paths*: a transition with more than [_maxPaths] simple paths marks
///   nothing.
library;

import 'dart:collection';
import 'dart:convert';

import 'package:nanoflow_model/nanoflow_model.dart';

import 'effect_places.dart';
import 'session_feed.dart';

/// The forks the shown effects went through on [body] and the edges
/// they took (effects design §5).
final class Passes {
  const Passes._(this._forks, this._taken, this._untaken);

  /// The passes of [effects] of [session] on [body], their nodes found by
  /// [places].
  ///
  /// Asked again of the same body, places and session while the session has
  /// not changed, with the same effects, it gives the same answer at once:
  /// the canvas asks every tick. Only the last answer for each body is kept;
  /// the paths found on the body are kept whatever is asked.
  factory Passes.of(
    GraphBody body, {
    required EffectPlaces places,
    required SessionData session,
    required Iterable<EffectState> effects,
  }) {
    final ids = [for (final effect in effects) effect.effectId];
    if (_asked[body] case final asked? when asked.isOf(places, session, ids)) {
      return asked.passes;
    }
    final passes = _passesOf(_Level.of(body), places, session, ids);
    _asked[body] = _Asked(places, session, session.changes, ids, passes);
    return passes;
  }

  static const none = Passes._({}, {}, {});

  final Map<String, int> _forks;
  final Set<int> _taken;
  final Set<int> _untaken;

  /// How many times the code went through the fork [nodeId]: once for each
  /// run of the code whose transitions passed it — publish and notify side
  /// by side after the same inspect went through the fork before them once,
  /// as did the effects after one wait —, as far as the journal tells the
  /// runs apart; 0 when none.
  int of(String nodeId) => _forks[nodeId] ?? 0;

  /// Whether the edge at [index] of `body.edges` was taken.
  bool taken(int index) => _taken.contains(index);

  /// Whether the edge at [index] leaves a passed fork and the code cannot
  /// have gone along it: it is on none of the ways the code may have gone —
  /// the walks of the transitions, through forks and calls, a walk
  /// and not a simple path since the code may go round a loop that runs no
  /// effect; on the body of a function the workflow calls, out of it and
  /// back in between any two effects; and the others of the library doc.
  /// Never on such a body when an effect node of it holds more than one of
  /// the effects shown.
  bool untaken(int index) => _untaken.contains(index);
}

/// The last answer for a body, and what it was asked of.
final class _Asked {
  _Asked(this.places, this.session, this.changes, this.ids, this.passes);

  final EffectPlaces places;
  final SessionData session;

  /// [SessionData.changes] of [session] then.
  final int changes;

  /// The ids of the effects shown, in their order.
  final List<String> ids;

  final Passes passes;

  bool isOf(EffectPlaces places, SessionData session, List<String> ids) {
    if (!identical(places, this.places) ||
        !identical(session, this.session) ||
        session.changes != changes ||
        ids.length != this.ids.length) {
      return false;
    }
    for (var i = 0; i < ids.length; i++) {
      if (ids[i] != this.ids[i]) return false;
    }
    return true;
  }
}

final Expando<_Asked> _asked = Expando('passes asked');

/// Which way of the code about an effect a run is (see [_Run]).
enum _Leg {
  /// From the body's start to the effect.
  into,

  /// On from the effect, through the body.
  on,

  /// From the body's start again, once the code left the body after the
  /// effect.
  again,

  /// To the effects after a wait from the effects it joined.
  join,
}

/// One run of the code a transition is part of: [leg] of the way about
/// [by] — for [_Leg.into] the effect the code came to, or on the workflow's
/// own body the `after` of it, for [_Leg.on] and [_Leg.again] the key of the
/// effect it came from, for [_Leg.join] the effects the wait joined —, or,
/// when [end], the way on from the effects that one came to, to the body's
/// end.
typedef _Run = ({String by, _Leg leg, bool end});

/// A way of the code over the level, from a node of [from] to a node of
/// [to] — `null` standing for the body's start among [from] and its end
/// among [to]: a transition, part of [run], when the code went that way; one
/// it may have gone, which marks nothing, when [run] is `null`. [failed] is
/// the outcome of the effect it leaves from, when it leaves from one: `true`
/// when that failed, `false` when it finished (see [_Level.between]).
typedef _Way = ({
  List<String?> from,
  List<String?> to,
  _Run? run,
  bool? failed,
});

Passes _passesOf(
  _Level level,
  EffectPlaces places,
  SessionData session,
  List<String> ids,
) {
  // The nodes of the level an effect is on or in, by its place and name.
  final nodes = <(String, String), List<String>>{};
  List<String> nodesOf(Effect effect) => switch (effect.place) {
    final place? => nodes[(place, effect.name)] ??= [
      for (final node in level.body.nodes)
        if (node is! ConditionNode && places.isIn(effect, node)) node.id,
    ],
    null => const [],
  };

  final tree = _Tree(session, places);
  // How [effect] ended, as the way out of a node with a failure route
  // tells it: `true` failed, `false` finished, `null` neither yet.
  bool? failedOf(Effect effect) => switch (session.stateOf(effect.id)?.status) {
    EffectStatus.failed => true,
    EffectStatus.finished => false,
    EffectStatus.running || null => null,
  };
  final shown = [
    for (final id in ids)
      if (session.effects[id] case final effect? when places.onGraph(effect))
        effect,
  ];
  final called = places.isCalled(level.body);
  final workflow = places.isWorkflow(level.body);
  final finished = session.state.status == SessionStatus.finished;

  final (:joins, :joined, :joinedBeside, :passed) = _joinsOf(
    level,
    session,
    tree,
    shown,
    nodesOf,
  );
  final ways = <_Way>[];
  // Each effect and its predecessor, both on the level and not in one call
  // node, and how the predecessor ended: the code may have left the body
  // between them.
  final pairs = <(List<String>, List<String>, bool?)>[];
  // The run that came to each effect, when not the one on from its
  // predecessor: its way to the body's end is one with those of the others
  // that run came to.
  final reached = <String, _Run>{};
  for (final effect in shown) {
    final at = nodesOf(effect);
    final (:before, :passedOver) = tree.before(effect);
    final previous = before == null ? const <String>[] : nodesOf(before);
    final failed = before == null ? null : failedOf(before);
    final join = joins[effect.id];
    // Where the code came from is not drawn, or not told: from the
    // predecessor, or from the start, the code may have come. So too when
    // the ends before the effect are all in one call node with it: ends
    // side by side in one millisecond join each other so.
    final unsure =
        passedOver ||
        passed.contains(effect.id) ||
        (join != null && join.from.isEmpty);
    _Run? sure(_Run run) => unsure ? null : run;
    if (join case (:final key, :final from) when from.isNotEmpty) {
      final run = reached[effect.id] = (by: key, leg: _Leg.join, end: false);
      for (final (:nodes, :drawn) in from) {
        ways.add((
          from: nodes,
          to: at,
          run: drawn ? sure(run) : null,
          failed: null,
        ));
      }
      // The effect before the wait may have ended a call all the same, and
      // this one begun the next.
      if (previous.isNotEmpty && !level.inOne(previous, at)) {
        pairs.add((previous, at, failed));
      }
    } else if (previous.isEmpty) {
      final into = reached[effect.id] = (
        by: workflow ? effect.after ?? '' : effect.id,
        leg: _Leg.into,
        end: false,
      );
      if (at.isNotEmpty) {
        ways.add((from: const [null], to: at, run: sure(into), failed: null));
      }
    } else if (at.isEmpty) {
      final on = (by: before!.key, leg: _Leg.on, end: false);
      ways.add((
        from: previous,
        to: const [null],
        run: sure(on),
        failed: failed,
      ));
    } else if (!level.inOne(previous, at)) {
      final on = (by: before!.key, leg: _Leg.on, end: false);
      if (level.leads(previous, at, failed: failed)) {
        ways.add((from: previous, to: at, run: sure(on), failed: failed));
      } else if (called &&
          level.leads(previous, const [null], failed: failed) &&
          level.leads(const [null], at)) {
        // Out of the body and into it again: the next call of its function.
        ways.add((
          from: previous,
          to: const [null],
          run: sure(on),
          failed: failed,
        ));
        final again = reached[effect.id] = (
          by: before.key,
          leg: _Leg.again,
          end: false,
        );
        ways.add((from: const [null], to: at, run: sure(again), failed: null));
      }
      pairs.add((previous, at, failed));
    }
  }
  // The effects the code ended up at: no effect on the graph follows them,
  // and none was joined before one.
  final open = <(List<String>, bool?)>[];
  for (final effect in shown) {
    if (!tree.isLast(effect) || joined.contains(effect.id)) continue;
    final at = nodesOf(effect);
    if (at.isEmpty) continue;
    // Joined only before effects that started in its millisecond, it may
    // have run beside them and been an end all the same.
    final beside = joinedBeside.contains(effect.id);
    if (!finished) {
      // From one that runs, the code has gone nowhere yet.
      if (session.stateOf(effect.id)?.finishedAt != null) {
        open.add((at, failedOf(effect)));
      }
      continue;
    }
    final (:by, :leg, end: _) =
        reached[effect.id] ??
        switch (effect.after) {
          final after? => (by: after, leg: _Leg.on, end: false),
          null => (by: effect.id, leg: _Leg.into, end: false),
        };
    final sure = !beside && !tree.isFollowedOffGraph(effect);
    ways.add((
      from: at,
      to: const [null],
      run: sure ? (by: by, leg: leg, end: true) : null,
      failed: failedOf(effect),
    ));
  }

  final runs = <String, Set<_Run>>{};
  final taken = <int>{};
  // The nodes with a failure route a transition went out of: passed, as
  // forks are, for what is darker.
  final exited = <String>{};
  for (final (:from, :to, :run, :failed) in ways) {
    if (run == null) continue;
    final (:way, corridor: _) = level.between(from, to, failed: failed);
    if (way == null) continue;
    exited.addAll(from.whereType<String>().where(level.hasFailureRoute));
    var (:forks, :edges) = way;
    // On the body of a function the workflow calls, the code may have left
    // the body after one effect and come into it again before the other:
    // what it went through is what both ways go through.
    if (called &&
        !from.contains(null) &&
        !to.contains(null) &&
        level.leads(from, const [null], failed: failed) &&
        level.leads(const [null], to)) {
      final out = level.between(from, const [null], failed: failed).way;
      final back = level.between(const [null], to).way;
      bool either(bool Function(_Through way) on) =>
          (out != null && on(out)) || (back != null && on(back));
      forks = {
        for (final fork in forks)
          if (either((way) => way.forks.contains(fork))) fork,
      };
      edges = {
        for (final edge in edges)
          if (either((way) => way.edges.contains(edge))) edge,
      };
    }
    taken.addAll(edges);
    for (final fork in forks) {
      (runs[fork] ??= {}).add(run);
    }
  }
  if (runs.isEmpty && taken.isEmpty && exited.isEmpty) return Passes.none;
  final forks = {
    for (final MapEntry(key: fork, value: by) in runs.entries) fork: by.length,
  };
  if (called && !_ranOnce(level, session, ids, nodesOf)) {
    return Passes._(forks, taken, const {});
  }
  final possible = _mayHaveGone(
    level,
    ways,
    pairs,
    open,
    called: called,
    finished: finished,
  );
  return Passes._(forks, taken, {
    for (final (i, edge) in level.body.edges.indexed)
      if ((forks.containsKey(edge.from) || exited.contains(edge.from)) &&
          !possible.contains(i))
        i,
  });
}

/// The edges the code may have gone along on [level], by their index in
/// `body.edges`: on these, no exit of a passed fork is darker. They are
///
/// - those on some walk of each of the [ways] — the transitions, and the
///   ways that mark nothing;
/// - on the body of a function the workflow calls ([called]), those of the
///   ways out of the body from one end of each of the [ways], and of each of
///   the [pairs] of an effect and its predecessor, and back into it to the
///   other, when both are there: the code may have left the body and come
///   into it again between any two effects;
/// - unless the session [finished], those of the ways from each of the
///   [open] effects — those that have finished, that no effect on the graph
///   follows and that were not joined before one, but for effects that
///   started in their millisecond — to any node, and on the
///   body of a function the workflow calls from the body's start to any
///   node: where the code went from there before it stopped, or after a
///   call began, the journal does not tell;
/// - and the edges of a fork by the outcome of one of those, or of a node
///   with a failure route by the label of one: the other branches of a
///   `Future.wait` there, which ran with it.
///
/// A way from an effect that failed or finished on a node with a failure
/// route leaves it as the effect ended ([_Way.failed]).
Set<int> _mayHaveGone(
  _Level level,
  List<_Way> ways,
  List<(List<String>, List<String>, bool?)> pairs,
  List<(List<String>, bool?)> open, {
  required bool called,
  required bool finished,
}) {
  final edges = <int>{};
  void outAndIn(List<String?> from, List<String?> to, bool? failed) {
    if (called &&
        level.leads(from, const [null], failed: failed) &&
        level.leads(const [null], to)) {
      edges
        ..addAll(level.between(from, const [null], failed: failed).corridor)
        ..addAll(level.between(const [null], to).corridor);
    }
  }

  for (final (:from, :to, run: _, :failed) in ways) {
    edges.addAll(level.between(from, to, failed: failed).corridor);
    outAndIn(from, to, failed);
  }
  for (final (from, to, failed) in pairs) {
    outAndIn(from, to, failed);
  }
  if (!finished) {
    for (final (from, failed) in open) {
      edges.addAll(level.onwards(from, failed: failed));
    }
    if (called) edges.addAll(level.onwards(const [null]));
  }
  return {...edges, ...level.besides(edges)};
}

/// Whether no effect node of [level] holds more than one of the effects
/// [ids] of [session]: the function whose body it is may have run once at
/// most, and run no effect in it again. Only then is an exit of a called
/// body darker.
bool _ranOnce(
  _Level level,
  SessionData session,
  List<String> ids,
  List<String> Function(Effect effect) nodesOf,
) {
  final held = <String>{};
  for (final id in ids) {
    final effect = session.effects[id];
    if (effect == null) continue;
    for (final node in nodesOf(effect)) {
      if (level.isEffect(node) && !held.add(node)) return false;
    }
  }
  return true;
}

/// The effects of a session on the graph as the tree their `after`s make,
/// passing over those not on it: each below the effect on the graph it
/// follows; those that follow none, or one no record has, below a root of
/// their own for that `after`.
final class _Tree {
  _Tree(this.session, this.places) {
    final below = <String, List<String>>{};
    for (final effect in session.effects.values) {
      final follows = _follows(effect);
      if (places.onGraph(effect)) {
        _of[effect.key] = follows;
        (below[follows.parent] ??= []).add(effect.key);
        if (follows.before case final before?) _followed.add(before.key);
      } else if (follows.before case final before?) {
        (_offGraph[before.key] ??= []).add(effect);
      }
    }
    var clock = 0;
    void tour(String root) {
      final stack = [(root, 0)];
      _in[root] = clock++;
      while (stack.isNotEmpty) {
        final (node, next) = stack.removeLast();
        final children = below[node] ?? const <String>[];
        if (next == children.length) {
          _out[node] = clock - 1;
          continue;
        }
        stack.add((node, next + 1));
        final child = children[next];
        if (_in.containsKey(child)) continue;
        _in[child] = clock++;
        stack.add((child, 0));
      }
    }

    for (final root in below.keys) {
      if (root.startsWith(_root)) tour(root);
    }
    // A ring of `after`s no root reaches: each of it a root.
    for (final key in _of.keys) {
      if (!_in.containsKey(key)) tour(key);
    }
  }

  final SessionData session;
  final EffectPlaces places;

  /// By the key of each effect on the graph, the effect on the graph it
  /// follows and whether it passed over effects not on it to get there, and
  /// what it is below.
  final Map<String, _Follows> _of = {};

  /// When each effect on the graph, by its key, and each root was come to on
  /// a walk of the tree, and the last that was come to below it.
  final Map<String, int> _in = {};
  final Map<String, int> _out = {};

  /// The keys of the effects on the graph an effect on the graph follows.
  final Set<String> _followed = {};

  /// By the key of each effect on the graph, the effects not on it that
  /// follow it, or one of them.
  final Map<String, List<Effect>> _offGraph = {};

  /// Starts the name of a root: no key of an effect does.
  static const _root = '\u0000';

  _Follows _follows(Effect effect) {
    var passedOver = false;
    final seen = <String>{};
    var key = effect.after;
    for (; key != null && seen.add(key); passedOver = true) {
      final record = session.effectWithKey(key);
      if (record == null) break;
      if (places.onGraph(record)) {
        return (before: record, passedOver: passedOver, parent: record.key);
      }
      key = record.after;
    }
    return (before: null, passedOver: passedOver, parent: '$_root${key ?? ''}');
  }

  /// The effect on the graph [effect], one on it, follows, passing over those
  /// not on it — [passedOver] when it did —; `null` when it follows none, or
  /// its `after` leads back to one no record has.
  ({Effect? before, bool passedOver}) before(Effect effect) {
    final (:before, :passedOver, parent: _) = _of[effect.key]!;
    return (before: before, passedOver: passedOver);
  }

  /// What [effect], one on the graph, is below: the effect it follows, or
  /// its root.
  String parentOf(Effect effect) => _of[effect.key]!.parent;

  /// When [effect], one on the graph, was come to on the walk.
  int at(Effect effect) => _in[effect.key]!;

  /// What was come to on the walk below what [effect], one on the graph, is
  /// below: the effects on the graph that follow the same, and those that
  /// follow them.
  ({int from, int to}) below(Effect effect) {
    final parent = parentOf(effect);
    return (from: _in[parent]! + 1, to: _out[parent]!);
  }

  /// Whether no effect on the graph follows [effect].
  bool isLast(Effect effect) => !_followed.contains(effect.key);

  /// Whether effects not on the graph follow [effect]: where the code went
  /// on is not drawn.
  bool isFollowedOffGraph(Effect effect) => _offGraph.containsKey(effect.key);

  /// When [effect], and the effects not on the graph that follow it, had
  /// all finished; `null` while one runs.
  DateTime? finishedAt(Effect effect) {
    var last = session.stateOf(effect.id)?.finishedAt;
    for (final follower in _offGraph[effect.key] ?? const <Effect>[]) {
      final finished = session.stateOf(follower.id)?.finishedAt;
      if (last == null || finished == null) return null;
      if (finished.isAfter(last)) last = finished;
    }
    return last;
  }
}

/// The effect on the graph an effect follows, passing over those not on it
/// — [passedOver] when it did —, and what it is below in the tree: that
/// effect's key, or a root.
typedef _Follows = ({Effect? before, bool passedOver, String parent});

/// The ends joined before an effect: [key] is the same for two effects only
/// when the same were joined before both, as before the effects after one
/// wait; [from] has the nodes of the level of those that lead to the effect
/// — one for each nodes they are on, none for those in one call node with
/// it, which lead to it inside —, `drawn` unless effects not on
/// the graph followed them.
typedef _Join = ({String key, List<({List<String> nodes, bool drawn})> from});

/// The ends joined before the effects [shown] of [session] on [level] (see
/// the library doc): [joins] has, by the id of each effect after a wait or
/// an awaited call, the ends joined before it; [joined] the ids of the ends
/// joined before some effect that started after them; [joinedBeside] those
/// of the ends joined only before effects that started in their own
/// millisecond, which they may have run beside; and [passed] the ids of the
/// effects before which ends would have been joined but for those passed
/// (below).
///
/// An end that was passed may have been passed by effects beside the effect
/// — as two calls of a function one after the other, or `Future.wait([x(),
/// helper()])` with helper's first effect later than x's last, leave the
/// journal —: where the code came to such an effect from the journal does
/// not tell.
///
/// An end joined before an effect that started before another and had
/// finished by the time it started is not joined before that one: the code
/// went from the end to the effect, and from there on — the first wait of
/// `await Future.wait([a(), b()]); if (c) await Future.wait([x(), y()]);
/// await z();` is not joined before z, the second is. So is an end joined
/// only beside the effect: effects side by side that end in the millisecond
/// they start pass each other (the library doc, «Limits»).
///
/// The ends are looked at by the nodes they are on: whether some lead to an
/// effect is asked once for each nodes of the ends and of the effects, and
/// how many of them below what an effect is below had finished by a time is
/// counted among those that had, in the order of the walk of the [tree].
({
  Map<String, _Join> joins,
  Set<String> joined,
  Set<String> joinedBeside,
  Set<String> passed,
})
_joinsOf(
  _Level level,
  SessionData session,
  _Tree tree,
  List<Effect> shown,
  List<String> Function(Effect effect) nodesOf,
) {
  final ends = <String, _Ends>{};
  final finishing = <({DateTime finished, _Ends ends, Effect effect})>[];
  final starting = <({DateTime started, List<String> at, Effect effect})>[];
  for (final effect in shown) {
    final at = nodesOf(effect);
    final state = session.stateOf(effect.id);
    if (at.isEmpty || state == null) continue;
    starting.add((started: state.startedAt, at: at, effect: effect));
    final finished = tree.finishedAt(effect);
    if (!tree.isLast(effect) || finished == null) continue;
    final passedOver = tree.isFollowedOffGraph(effect);
    final of = ends['${passedOver ? 1 : 0}${at.join('\u0000')}'] ??= _Ends(
      ends.length,
      at,
      passedOver: passedOver,
    );
    of.walked.add(tree.at(effect));
    finishing.add((finished: finished, ends: of, effect: effect));
  }
  final joins = <String, _Join>{};
  final joined = <String>{};
  final beside = <String>{};
  final passed = <String>{};
  if (finishing.isEmpty) {
    return (joins: joins, joined: joined, joinedBeside: beside, passed: passed);
  }
  for (final of in ends.values) {
    of.walked.sort();
  }
  finishing.sort((a, b) => a.finished.compareTo(b.finished));
  starting.sort((a, b) => a.started.compareTo(b.started));
  // By the nodes of an effect, the ends that lead to it, or from which the
  // code may have gone to it inside a call node.
  final leading = <String, List<_Ends>>{};
  // The ends joined before an effect, by when it finished: from then on they
  // are joined before no effect that started later than it did — an end that
  // started in its millisecond too, though the two may have run beside each
  // other (the library doc, «Limits»).
  final passing =
      SplayTreeMap<DateTime, List<({DateTime started, _Ends of, int walk})>>();
  var next = 0;
  for (final (:started, :at, :effect) in starting) {
    for (; next < finishing.length; next++) {
      final (:finished, ends: of, effect: end) = finishing[next];
      if (finished.isAfter(started)) break;
      of.finish(tree.at(end), end.id);
    }
    for (
      var time = passing.firstKey();
      time != null && !time.isAfter(started);
      time = passing.firstKeyAfter(time)
    ) {
      passing[time]!.removeWhere((passed) {
        if (!passed.started.isBefore(started)) return false;
        passed.of.pass(passed.walk);
        return true;
      });
      if (passing[time]!.isEmpty) passing.remove(time);
    }
    final (:from, :to) = tree.below(effect);
    final itself = tree.at(effect);
    final finished = session.stateOf(effect.id)?.finishedAt;
    final counts = <int>[];
    var left = false;
    final joinedFrom = <({List<String> nodes, bool drawn})>[];
    for (final of in leading[at.join('\u0000')] ??= [
      for (final of in ends.values)
        if (level.inOne(of.nodes, at) || level.leads(of.nodes, at)) of,
    ]) {
      final count = of.count(from, to, besides: itself);
      if (count == 0) continue;
      counts.addAll([of.index, count]);
      final walks = of.left(from, to, besides: itself);
      if (walks.isEmpty) continue;
      left = true;
      if (!level.inOne(of.nodes, at)) {
        joinedFrom.add((nodes: of.nodes, drawn: !of.passedOver));
      }
      for (final id in of.join(walks)) {
        // An end that started in the millisecond the effect did may have run
        // beside it.
        if (session.stateOf(id)?.startedAt == started) {
          beside.add(id);
        } else {
          joined.add(id);
        }
      }
      if (finished != null) {
        (passing[finished] ??= []).addAll([
          for (final walk in walks) (started: started, of: of, walk: walk),
        ]);
      }
    }
    if (left) {
      joins[effect.id] = (
        key: jsonEncode([tree.parentOf(effect), counts]),
        from: joinedFrom,
      );
    } else if (counts.isNotEmpty) {
      passed.add(effect.id);
    }
  }
  return (
    joins: joins,
    joined: joined,
    joinedBeside: beside.difference(joined),
    passed: passed,
  );
}

/// The ends of a level on the same nodes of it, and whether effects not on
/// the graph followed them: when each was come to on the walk of the tree of
/// the session, which of them had finished by now, and which of those were
/// passed: joined before an effect that had finished since.
final class _Ends {
  _Ends(this.index, this.nodes, {required this.passedOver});

  final int index;
  final List<String> nodes;
  final bool passedOver;

  /// When each was come to on the walk, in order, once all are added.
  final List<int> walked = [];

  /// How many had finished by now, by their place in [walked].
  late final _Counts _finished = _Counts(walked.length);

  /// Those that had finished by now and were not passed, by their place in
  /// [walked], with their ids.
  final SplayTreeMap<int, String> _left = SplayTreeMap();

  /// The end [id], come to on the walk at [walk], had finished by now.
  void finish(int walk, String id) {
    _finished.add(_place(walk));
    _left[walk] = id;
  }

  /// How many that had finished by now were come to on the walk from [from]
  /// to [to], but for the one come to at [besides].
  int count(int from, int to, {required int besides}) =>
      _finished.upTo(_place(to + 1)) -
      _finished.upTo(_place(from)) -
      (from <= besides &&
              besides <= to &&
              _place(besides) < walked.length &&
              walked[_place(besides)] == besides &&
              _finished.has(_place(besides))
          ? 1
          : 0);

  /// The walks of those that had finished by now and were not passed, come
  /// to on the walk from [from] to [to], but for the one come to at
  /// [besides].
  List<int> left(int from, int to, {required int besides}) => [
    for (
      var walk = _left.firstKeyAfter(from - 1);
      walk != null && walk <= to;
      walk = _left.firstKeyAfter(walk)
    )
      if (walk != besides) walk,
  ];

  /// The ids of those at [walks].
  Iterable<String> join(List<int> walks) => [
    for (final walk in walks) _left[walk]!,
  ];

  /// The one at [walk] was passed.
  void pass(int walk) => _left.remove(walk);

  /// How many of them were come to on the walk before [walk].
  int _place(int walk) {
    var low = 0;
    var high = walked.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (walked[middle] < walk) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}

/// Which of [length] places are counted, and how many up to a place: a
/// Fenwick tree.
final class _Counts {
  _Counts(int length) : _tree = List.filled(length + 1, 0), _set = {};

  final List<int> _tree;
  final Set<int> _set;

  void add(int place) {
    if (!_set.add(place)) return;
    for (var i = place + 1; i < _tree.length; i += i & -i) {
      _tree[i]++;
    }
  }

  bool has(int place) => _set.contains(place);

  /// How many of the places before [place] are counted.
  int upTo(int place) {
    var count = 0;
    for (var i = place; i > 0; i -= i & -i) {
      count += _tree[i];
    }
    return count;
  }
}

/// What every path of a transition goes through: the forks, and the edges by
/// their index in `body.edges`.
typedef _Through = ({Set<String> forks, Set<int> edges});

/// A transition as the level has it: what every simple path of it goes
/// through — `null` when there is no path, there are more than [_maxPaths],
/// or nothing is on every one —; and its corridor, the edges on some walk
/// of it.
typedef _Between = ({_Through? way, Set<int> corridor});

/// A transition with more simple paths than this gives no marks: a body
/// whose forks multiply the ways between two effects past it is not searched
/// to the end.
const _maxPaths = 1000;

/// A body's nodes and edges as the search for paths reads them, and the
/// transitions found, kept for as long as the body is.
final class _Level {
  _Level._(this.body)
    : _nodes = {for (final node in body.nodes) node.id: node},
      _out = {},
      _in = {} {
    for (final (i, edge) in body.edges.indexed) {
      (_out[edge.from] ??= []).add(i);
      (_in[edge.to] ??= []).add(i);
      if (edge.failed) _failing.add(edge.from);
    }
  }

  static _Level of(GraphBody body) => _levels[body] ??= _Level._(body);

  static final Expando<_Level> _levels = Expando('passes levels');

  final GraphBody body;
  final Map<String, GraphNode> _nodes;

  /// The edges leaving each node, by index; `null` for the body's start.
  final Map<String?, List<int>> _out;

  /// The edges entering each node, by index; `null` for the body's end.
  final Map<String?, List<int>> _in;

  final Map<String, _Between> _between = {};

  /// The nodes with a failure route: edges `failed` leave them.
  final Set<String?> _failing = {};

  bool isEffect(String id) => _nodes[id] is EffectNode;

  /// Whether the node [id] has a failure route.
  bool hasFailureRoute(String id) => _failing.contains(id);

  /// Whether a way from [node] may leave it by the edge [i], when the effect
  /// it leaves from [failed], or finished when `false`: by the edges of the
  /// failure route only when the effect failed, by the others only when it
  /// finished. A way from a call, from an effect that neither failed nor
  /// finished, or from a node without a failure route leaves by any.
  bool _leaves(String? node, int i, bool? failed) =>
      failed == null ||
      !_failing.contains(node) ||
      _nodes[node] is! EffectNode ||
      body.edges[i].failed == failed;

  /// Whether [from] and [to] share a call node: a transition between them
  /// may be inside it.
  bool inOne(List<String> from, List<String> to) =>
      from.any((id) => to.contains(id) && _nodes[id] is CallNode);

  /// Whether a path may go through [id]: a fork, a call that may have run
  /// no effects; never an effect node, or there would be an effect between
  /// the two.
  bool _passable(String id) => switch (_nodes[id]) {
    ConditionNode() || CallNode() => true,
    EffectNode() || null => false,
  };

  /// Whether some way leads from a node of [from] to a node of [to] through
  /// forks and calls: the corridor of the transition is not empty. [failed]
  /// as for [between].
  bool leads(List<String?> from, List<String?> to, {bool? failed}) =>
      between(from, to, failed: failed).corridor.isNotEmpty;

  /// The transition from a node of [from] to a node of [to] — `null`
  /// standing for the body's start among [from] and its end among [to]:
  /// what every simple path of it goes through, `null` when there is no
  /// path, more than [_maxPaths], or nothing is on every one; and its
  /// corridor. When it leaves from an effect that [failed] — or finished,
  /// when `false` —, it leaves an effect node with a failure route as the
  /// effect ended ([_leaves]).
  _Between between(List<String?> from, List<String?> to, {bool? failed}) {
    final targets = to.toSet();
    return _between[jsonEncode([from, to, failed])] ??= (
      way: _search(from, targets, failed),
      corridor: _corridor(from, targets, failed),
    );
  }

  /// The edges on some walk from a node of [from] through forks and calls
  /// to any node, or the body's end: those leaving [from] and the nodes such
  /// a walk reaches. [failed] as for [between].
  Set<int> onwards(List<String?> from, {bool? failed}) {
    final reached = <String?>{...from};
    final ahead = [...from];
    final edges = <int>{};
    while (ahead.isNotEmpty) {
      final node = ahead.removeLast();
      for (final i in _out[node] ?? const <int>[]) {
        if (!_leaves(node, i, failed)) continue;
        edges.add(i);
        final next = body.edges[i].to;
        if (next != null && _passable(next) && reached.add(next)) {
          ahead.add(next);
        }
      }
    }
    return edges;
  }

  /// The edges of a fork by the outcome of one of [edges] but for those, or
  /// of a node with a failure route by the label of one: the edges of one
  /// outcome to more than one node are the branches of a `Future.wait`,
  /// which the code goes along together. An outcome of a fork without a
  /// label tells nothing.
  Iterable<int> besides(Set<int> edges) sync* {
    for (final i in edges) {
      final GraphEdge(:from, :label, :failed) = body.edges[i];
      final ways = _nodes[from] is ConditionNode
          ? label != null
          : _failing.contains(from);
      if (!ways) continue;
      for (final j in _out[from] ?? const <int>[]) {
        final other = body.edges[j];
        if (j != i && other.label == label && other.failed == failed) yield j;
      }
    }
  }

  /// The edges on some walk from a node of [from] to a node of [to] through
  /// forks and calls: nodes may come again on a walk, so the rounds
  /// of a loop that run no effect are on one. Each edge leaves a node a
  /// source reaches and enters a target, or a node that reaches one.
  Set<int> _corridor(List<String?> from, Set<String?> to, bool? failed) {
    final edges = body.edges;
    final reached = <String?>{...from};
    final ahead = [...from];
    // The edges a walk leaves its sources by.
    final out = <int>{};
    while (ahead.isNotEmpty) {
      final node = ahead.removeLast();
      for (final i in _out[node] ?? const <int>[]) {
        if (!_leaves(node, i, failed)) continue;
        out.add(i);
        final next = edges[i].to;
        if (next != null && _passable(next) && reached.add(next)) {
          ahead.add(next);
        }
      }
    }
    final leading = <String>{};
    final behind = [...to];
    while (behind.isNotEmpty) {
      for (final i in _in[behind.removeLast()] ?? const <int>[]) {
        final prior = edges[i].from;
        if (prior != null && _passable(prior) && leading.add(prior)) {
          behind.add(prior);
        }
      }
    }
    return {
      for (final (i, edge) in edges.indexed)
        if (reached.contains(edge.from) &&
            out.contains(i) &&
            (to.contains(edge.to) || leading.contains(edge.to)))
          i,
    };
  }

  _Through? _search(List<String?> from, Set<String?> to, bool? failed) {
    final edges = body.edges;
    final path = <int>[];
    final on = <String>{};
    Set<String>? forks;
    Set<int>? onEvery;
    var count = 0;

    // Whether a path from [source] ends at [id]: a target not on it, or
    // [source] itself, round a loop.
    bool ends(String? id, String? source) =>
        to.contains(id) && (id == null || id == source || !on.contains(id));

    // Whether a path from [source] goes on from [id], which is on it, to a
    // target: a search that only goes on where it leads somewhere takes as
    // long as the paths it finds, however many ways lead nowhere.
    bool leadsOn(String id, String? source) {
      final seen = {id};
      final queue = [id];
      while (queue.isNotEmpty) {
        for (final i in _out[queue.removeLast()] ?? const <int>[]) {
          final next = edges[i].to;
          if (ends(next, source)) return true;
          if (next != null &&
              !on.contains(next) &&
              _passable(next) &&
              seen.add(next)) {
            queue.add(next);
          }
        }
      }
      return false;
    }

    // Walks on from [node]; false once the paths are too many, or nothing
    // is on every one.
    bool walk(String? node, String? source) {
      for (final i in _out[node] ?? const <int>[]) {
        if (!_leaves(node, i, failed)) continue;
        final next = edges[i].to;
        path.add(i);
        if (ends(next, source)) {
          if (++count > _maxPaths) return false;
          final forksOn = {
            for (final j in path)
              if (edges[j].to case final id? when _nodes[id] is ConditionNode)
                id,
          };
          if (forks == null || onEvery == null) {
            forks = forksOn;
            onEvery = {...path};
          } else {
            forks!.retainAll(forksOn);
            onEvery!.retainAll(path);
            if (forks!.isEmpty && onEvery!.isEmpty) return false;
          }
        }
        if (next != null && _passable(next) && on.add(next)) {
          final more = !leadsOn(next, source) || walk(next, source);
          on.remove(next);
          if (!more) return false;
        }
        path.removeLast();
      }
      return true;
    }

    for (final source in from) {
      on
        ..clear()
        ..addAll([?source]);
      path.clear();
      if (!walk(source, source)) return null;
    }
    return count == 0 ? null : (forks: forks!, edges: onEvery!);
  }
}
