/// Which forks of the level drawn a session's code went through, and which
/// edges it took (effects design §5), read from the journal alone: under the
/// rule that every side effect is in an effect, the code between two effects
/// goes one way, set by what the effects gave, and an effect's `after` names
/// the effect before it in its context. So each shown effect and its
/// predecessor are a transition along the level's edges, and what lies on
/// every way the transition could have gone was passed. No condition is
/// evaluated. Pure.
///
/// An effect is on the level at the nodes it is on or in, as for the marks
/// (spec §9 «Эффекты на графе»), or outside it. A transition goes:
///
/// - from the body's start to the effect when its predecessor is outside
///   the level, or there is none — no `after`, or one no record has;
/// - from the effects a wait joined before the effect, when there are some
///   on the level, instead of from its predecessor, in one run: after
///   `await Future.wait([...])` the library keys the next effect after the
///   effect before the wait, as it keys the effects waited for; so the
///   effects shown after its predecessor, started before it, that lead to it
///   on the level were joined before it — they lead to it, not to the end;
/// - from the predecessor to the effect when both are on the level, unless
///   they are in one call or one copies node: then it is inside it;
/// - but on the body of a function the workflow calls, when no way leads
///   from the predecessor to the effect in it, from the predecessor to the
///   body's end and from the body's start to the effect, a run of its own:
///   the code left the body and came into it again, as two calls of the
///   function one after the other with no effect between them do — only
///   when both ways are there;
/// - from the predecessor to the body's end when the effect is outside;
/// - and, once the session has finished, from each effect on the level that
///   no effect follows, nor was joined, to the body's end — not from a
///   copies node: copies end, and the effect after their `Future.wait`
///   follows the effect before them.
///
/// An effect not on the graph at all — without a place, or at no node —
/// makes no transition, to it or from it: where the code went there is not
/// drawn.
///
/// On the body of a function the workflow calls, the code may have left the
/// body and come into it again between any two effects, even when a way
/// leads from one to the other in it: for each transition, and each effect
/// and its predecessor, the edges of the ways out of the body from the one
/// and back into it to the other, when both are there, are ones the code
/// may have taken too — no exit on them is darker, though they mark
/// nothing.
library;

import 'dart:convert';
import 'dart:math' show max;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'effect_places.dart';
import 'session_feed.dart';

/// The forks the shown effects went through on [body] and the edges
/// they took (effects design §5).
final class Passes {
  const Passes._(this._forks, this._taken, this._untaken);

  /// The passes of [effects] of [session] — all of it, a copy, all copies —
  /// on [body], their nodes found by [places].
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
  /// transition that passed it, but once for all those from one effect —
  /// publish and notify side by side after the same inspect went through
  /// the fork before them once —, and once more for all those from it back
  /// into the body after the code left it; 0 when none.
  int of(String nodeId) => _forks[nodeId] ?? 0;

  /// Whether the edge at [index] of `body.edges` was taken.
  bool taken(int index) => _taken.contains(index);

  /// Whether the edge at [index] leaves a passed fork and no transition
  /// could have taken it: it is on no walk of any transition from where the
  /// transition starts to where it ends through forks, calls and copies —
  /// a walk, not a simple path, since the code may go round a loop that runs
  /// no effect.
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

  /// To the effect from the effects a wait joined before it.
  join,
}

/// One run of the code a transition is part of: [leg] of the way about the
/// effect [id]. The transitions on from one effect are one run: the code
/// after an effect runs once, and splits only where effects are called side
/// by side; so are those back into the body after it, and those from the
/// effects a wait joined to one effect.
typedef _Run = ({String id, _Leg leg});

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

  final transitions = <({_Run run, List<String?> from, List<String?> to})>[];
  void add(_Run run, List<String?> from, List<String?> to) =>
      transitions.add((run: run, from: from, to: to));

  // On the body of a function the workflow calls, the ways the code may
  // have gone besides the transitions: out of the body and into it again.
  // They mark nothing.
  final called = places.isCalled(level.body);
  final also = <(List<String?>, List<String?>)>[];
  void outAndIn(List<String?> from, List<String?> to) {
    if (called &&
        level.leads(from, const [null]) &&
        level.leads(const [null], to)) {
      also
        ..add((from, const [null]))
        ..add((const [null], to));
    }
  }

  final (:joins, :joined) = _joinsOf(level, session, ids, nodesOf);
  for (final id in ids) {
    final effect = session.effects[id];
    if (effect == null || !places.onGraph(effect)) continue;
    final before = switch (effect.after) {
      final key? => session.effectWithKey(key),
      null => null,
    };
    if (before != null && !places.onGraph(before)) continue;
    final at = nodesOf(effect);
    final previous = before == null ? const <String>[] : nodesOf(before);
    if (joins[id] case final waited?) {
      for (final from in waited) {
        add((id: id, leg: _Leg.join), from, at);
      }
      // The effect before the wait may have ended a call all the same, and
      // this one begun the next.
      if (previous.isNotEmpty && !level.inOne(previous, at)) {
        outAndIn(previous, at);
      }
    } else if (previous.isEmpty) {
      if (at.isNotEmpty) add((id: id, leg: _Leg.into), const [null], at);
    } else if (at.isEmpty) {
      add((id: before!.id, leg: _Leg.on), previous, const [null]);
    } else if (!level.inOne(previous, at)) {
      final on = (id: before!.id, leg: _Leg.on);
      if (level.leads(previous, at)) {
        add(on, previous, at);
      } else if (called &&
          level.leads(previous, const [null]) &&
          level.leads(const [null], at)) {
        // Out of the body and into it again: the next call of its function.
        add(on, previous, const [null]);
        add((id: before.id, leg: _Leg.again), const [null], at);
      }
      outAndIn(previous, at);
    }
  }
  if (session.state.status == SessionStatus.finished) {
    final followed = {
      for (final effect in session.effects.values) ?effect.after,
    };
    for (final id in ids) {
      final effect = session.effects[id];
      if (effect == null ||
          followed.contains(effect.key) ||
          joined.contains(id)) {
        continue;
      }
      final at = nodesOf(effect);
      if (at.isEmpty || at.any(level.isCopies)) continue;
      add((id: id, leg: _Leg.on), at, const [null]);
    }
  }
  for (final (run: _, :from, :to) in [...transitions]) {
    outAndIn(from, to);
  }

  final runs = <String, Set<_Run>>{};
  final taken = <int>{};
  // The edges some transition may have taken, those of transitions that
  // mark nothing too, and those of the ways out and back in.
  final possible = {
    for (final (from, to) in also) ...level.between(from, to).corridor,
  };
  for (final (:run, :from, :to) in transitions) {
    final (:way, :corridor) = level.between(from, to);
    possible.addAll(corridor);
    if (way == null) continue;
    taken.addAll(way.edges);
    for (final fork in way.forks) {
      (runs[fork] ??= {}).add(run);
    }
  }
  if (runs.isEmpty && taken.isEmpty) return Passes.none;
  final forks = {
    for (final MapEntry(key: fork, value: by) in runs.entries) fork: by.length,
  };
  return Passes._(forks, taken, {
    for (final (i, edge) in level.body.edges.indexed)
      if (forks.containsKey(edge.from) && !possible.contains(i)) i,
  });
}

/// The waits the effects [ids] of [session] were joined by, on [level]:
/// after `await Future.wait([...])` the library keys the next effect after
/// the effect before the wait, as it keys the effects waited for. So of the
/// effects shown after one effect of the session, those started before
/// another that lead to it on the level were joined before it: [joins] has,
/// by its id, the
/// nodes of each such — one for each nodes they are on, none for those in
/// one call or copies node with it, which lead to it inside —, and [joined]
/// the ids of those joined.
///
/// The effects after one effect are looked at by the nodes they are on:
/// whether some lead to others is asked once for each two of those.
({Map<String, List<List<String>>> joins, Set<String> joined}) _joinsOf(
  _Level level,
  SessionData session,
  List<String> ids,
  List<String> Function(Effect effect) nodesOf,
) {
  final order = {for (final (i, id) in ids.indexed) id: i};
  final byAfter = <String, List<Effect>>{};
  for (final id in ids) {
    if (session.effects[id] case Effect(:final after?) && final effect
        when session.effectWithKey(after) != null) {
      (byAfter[after] ??= []).add(effect);
    }
  }
  final joins = <String, List<List<String>>>{};
  final joined = <String>{};
  for (final group in byAfter.values) {
    if (group.length < 2) continue;
    // The effects of the group on the level by the nodes they are on, each
    // in the order they started.
    final on = <String, ({List<String> nodes, List<String> ids})>{};
    for (final effect in group) {
      final at = nodesOf(effect);
      if (at.isEmpty) continue;
      (on[at.join('\u0000')] ??= (nodes: at, ids: [])).ids.add(effect.id);
    }
    for (final source in on.values) {
      final first = order[source.ids.first]!;
      // The last of those [source] leads to: those of it started before
      // were joined.
      var last = -1;
      for (final target in on.values) {
        if (!level.leads(source.nodes, target.nodes)) continue;
        last = max(last, order[target.ids.last]!);
        final inside = level.inOne(source.nodes, target.nodes);
        for (final id in target.ids) {
          if (order[id]! <= first) continue;
          final from = joins[id] ??= [];
          if (!inside) from.add(source.nodes);
        }
      }
      for (final id in source.ids) {
        if (order[id]! < last) joined.add(id);
      }
    }
  }
  return (joins: joins, joined: joined);
}

/// What every path of a transition goes through: the forks, and the edges by
/// their index in `body.edges`.
typedef _Way = ({Set<String> forks, Set<int> edges});

/// A transition as the level has it: what every simple path of it goes
/// through, `null` when there is none or there are too many; and its
/// corridor, the edges on some walk of it.
typedef _Between = ({_Way? way, Set<int> corridor});

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

  bool isCopies(String id) => _nodes[id] is CopiesNode;

  /// Whether [from] and [to] share a call or copies node: a transition
  /// between them may be inside it.
  bool inOne(List<String> from, List<String> to) => from.any(
    (id) =>
        to.contains(id) && (_nodes[id] is CallNode || _nodes[id] is CopiesNode),
  );

  /// Whether a path may go through [id]: a fork, a call that may have run
  /// no effects, copies run whole; never an effect node, or there would be
  /// an effect between the two.
  bool _passable(String id) => switch (_nodes[id]) {
    ConditionNode() || CallNode() || CopiesNode() => true,
    EffectNode() || null => false,
  };

  /// Whether some way leads from a node of [from] to a node of [to] through
  /// forks, calls and copies: the corridor of the transition is not empty.
  bool leads(List<String?> from, List<String?> to) =>
      between(from, to).corridor.isNotEmpty;

  /// The transition from a node of [from] to a node of [to] — `null`
  /// standing for the body's start among [from] and its end among [to]:
  /// what every simple path of it goes through, `null` when there is no
  /// path or more than [_maxPaths]; and its corridor.
  _Between between(List<String?> from, List<String?> to) {
    final targets = to.toSet();
    return _between[jsonEncode([from, to])] ??= (
      way: _search(from, targets),
      corridor: _corridor(from, targets),
    );
  }

  /// The edges on some walk from a node of [from] to a node of [to] through
  /// forks, calls and copies: nodes may come again on a walk, so the rounds
  /// of a loop that run no effect are on one. Each edge leaves a node a
  /// source reaches and enters a target, or a node that reaches one.
  Set<int> _corridor(List<String?> from, Set<String?> to) {
    final edges = body.edges;
    final reached = <String?>{...from};
    final ahead = [...from];
    while (ahead.isNotEmpty) {
      for (final i in _out[ahead.removeLast()] ?? const <int>[]) {
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
            (to.contains(edge.to) || leading.contains(edge.to)))
          i,
    };
  }

  _Way? _search(List<String?> from, Set<String?> to) {
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
