/// The copies of a `copies` frame in a session (spec §9 «Копии», decisions
/// 10 and 11): the body run side by side, once for each item of a list.
///
/// A copy is a chain of the frame's effects by `after`: its first effect is one
/// whose predecessor — the effect whose key its record's `after` is — lies
/// outside the frame (an effect at no place the frame holds, or none at all);
/// every other effect of the frame belongs to the copy of its predecessor. A
/// rerun rewrites a record's `after`: the chain follows the record as it is
/// now. Copies are numbered by when they started. Pure.
///
/// The limit of this: a copy of an outer frame is told by its first effect.
/// One with no effect before its inner copies — `Future.wait([for (p in pkgs)
/// Future.wait([for (t in targets) f.effect('build', …)])])` — cannot be told
/// apart: each effect of its inner copies follows an effect outside both
/// frames, and so starts an outer copy of its own. And a frame holds its
/// effects by place, not by the way they were called: a function with effects
/// called both inside a frame and outside it is the frame's, and each chain of
/// its call outside is a copy of the frame too.
library;

import 'dart:collection';
import 'dart:convert';

import 'package:nanoflow_model/nanoflow_model.dart';

import 'body_path.dart';
import 'effect_places.dart';
import 'session_feed.dart';

/// How a copy stands, as its effects tell.
enum CopyStatus {
  /// An effect of it runs.
  running,

  /// An effect of it was running when the process of its session went.
  interrupted,

  /// Its effects have finished.
  finished,

  /// An effect of it failed: the last time it ran, it threw.
  failed,
}

/// One copy of a frame: its effects, and how it stands.
final class Copy {
  Copy._(this.number, this.first, List<EffectState> effects, this.status)
    : effects = List.unmodifiable(effects),
      _ids = {for (final effect in effects) effect.effectId};

  /// From 1, in the order the copies started.
  final int number;

  /// The effect that started the copy: its predecessor is outside the frame.
  final EffectState first;

  /// The copy's effects in the order of their first `effect-started`.
  final List<EffectState> effects;

  final CopyStatus status;

  final Set<String> _ids;

  /// The copy's id: that of its [first] effect.
  String get id => first.effectId;

  /// The document with the output of the [first] effect, which hints at
  /// which copy it is (`core:uploaded`); `null` until that effect finished.
  String? get hintDocument => first.outputId;

  /// Whether the effect [effectId] is one of the copy's.
  bool contains(String effectId) => _ids.contains(effectId);
}

/// The copies of [frame] among [effects] of [session] (by default, all of its
/// effects): those at the places [places] says the frame holds, in chains by
/// `after`, numbered by the time of their first `effect-started`. An effect
/// whose record has not been given is in none.
List<Copy> copiesOf(
  CopiesNode frame, {
  required EffectPlaces places,
  required SessionData session,
  Iterable<EffectState>? effects,
}) {
  final held = places.within(frame);
  bool inside(Effect? record) => places.of(record).any(held.contains);

  // The first effect of the copy of each effect, by id: every effect walked
  // gets it, so that each chain is walked once.
  final firsts = <String, String>{};
  String firstOf(Effect record) {
    final walked = <String>{};
    var effect = record;
    String first;
    while (true) {
      final known = firsts[effect.id];
      if (known != null) {
        first = known;
        break;
      }
      walked.add(effect.id);
      final after = effect.after;
      final before = after == null ? null : session.effectWithKey(after);
      if (before == null || !inside(before) || walked.contains(before.id)) {
        first = effect.id;
        break;
      }
      effect = before;
    }
    for (final id in walked) {
      firsts[id] = first;
    }
    return first;
  }

  final chains = <String, List<EffectState>>{};
  for (final effect in effects ?? session.state.effects) {
    final record = session.effects[effect.effectId];
    if (!inside(record)) continue;
    (chains[firstOf(record!)] ??= []).add(effect);
  }
  final started = [
    for (final MapEntry(key: first, value: chain) in chains.entries)
      (
        first: session.stateOf(first) ?? chain.first,
        chain: chain,
        at: chain
            .map((effect) => effect.startedAt)
            .reduce((a, b) => b.isBefore(a) ? b : a),
      ),
  ];
  // A stable sort: copies that started together keep the order of their
  // effects.
  final order = [for (var i = 0; i < started.length; i++) i]
    ..sort((a, b) {
      final byTime = started[a].at.compareTo(started[b].at);
      return byTime != 0 ? byTime : a.compareTo(b);
    });
  return [
    for (final (n, i) in order.indexed)
      Copy._(
        n + 1,
        started[i].first,
        started[i].chain,
        _statusOf(started[i].chain, interrupted: session.interrupted),
      ),
  ];
}

/// The loop variable of the label of [frame], `pkg` of `pkg in packages`;
/// `null` when it names none.
String? _variableOf(CopiesNode frame) =>
    RegExp(r'^([A-Za-z_$][A-Za-z0-9_$]*) in ').firstMatch(frame.label)?[1];

/// What the copy [number] of [frame] is called in a path: its loop variable
/// and number, `pkg 2`; `copy 2` when the frame's label names no variable.
String copyName(CopiesNode frame, int number) =>
    '${_variableOf(frame) ?? 'copy'} $number';

/// A `copies` frame the canvas goes down through: a level opened from a
/// `copies` node, with the copies of it the session ran and the one
/// selected (decision 11).
///
/// Copies in copies are numbered within the copy of the frame around them:
/// `pkg 2 › target 1`. While that frame shows all its copies, the copies of
/// this one cannot be told apart by number alone, and none can be chosen
/// ([choosable]): a copy of the frame around is chosen first.
final class CopiesFrame {
  CopiesFrame._({
    required this.node,
    required this.depth,
    required List<Copy> copies,
    required this.around,
    required this.selected,
    required this.footer,
  }) : copies = List.unmodifiable(copies);

  final CopiesNode node;

  /// The level the frame's body is: its index among the canvas's levels.
  final int depth;

  /// The copies among the effects shown, each numbered within the copy of
  /// the frame around it.
  final List<Copy> copies;

  /// The frame around this one that shows all its copies, so that none of
  /// this one's can be chosen; `null` when one can.
  final CopiesNode? around;

  /// The copy shown; `null` for all.
  final Copy? selected;

  /// Under the frame: `done 1 of 3` for all; `pkg 2 · now verify`, or
  /// `pkg 2 · interrupted at verify` once the process is gone, for one.
  final String footer;

  /// Whether one of [copies] can be chosen: no frame around shows all.
  bool get choosable => around == null;

  /// Over the frame: `each pkg in packages`.
  String get title => 'each ${node.label}';

  /// Across from the [title]: `×3 · in parallel`.
  String get countText => '×${copies.length} · in parallel';

  /// What [copy] is called: `pkg 2`.
  String nameOf(Copy copy) => copyName(node, copy.number);

  /// What the switcher says while no copy can be chosen: `choose the outer
  /// pkg first` — the frame round it may be a level up or drawn round it in
  /// place.
  String? get chooseFirst => switch (around) {
    final around? => 'choose the outer ${_variableOf(around) ?? 'copy'} first',
    null => null,
  };
}

/// The copies of a `copies` node of the level drawn, which is not opened,
/// or of one inside it — in the body of copies, or of a function a call
/// calls — each numbered within the copy around it: they name the effects in
/// them.
typedef LevelCopies = ({CopiesNode node, List<Copy> copies});

/// What the levels of the canvas show of a session: the copies frames they
/// go down through, and the effects shown — those of the copy selected in
/// each frame, all effects when none is.
final class ShownEffects {
  ShownEffects._(this.frames, this.levelCopies, this.effects)
    : _paths = _pathsOf(frames, levelCopies);

  final List<CopiesFrame> frames;

  /// The copies of the `copies` nodes of the level drawn and inside them,
  /// the outer before the inner.
  final List<LevelCopies> levelCopies;

  /// The effects shown, in the order of their first `effect-started`.
  final List<EffectState> effects;

  /// These with only those of the [effects] [test] keeps: the same frames
  /// and copies, fewer effects shown.
  ShownEffects where(bool Function(EffectState effect) test) => ShownEffects._(
    frames,
    levelCopies,
    List.unmodifiable(effects.where(test)),
  );

  /// The names of the copies each effect is in, frame by frame, with the
  /// depth of the frame where it is the copy shown; `null` for any other.
  final Map<String, List<_Part>> _paths;

  static Map<String, List<_Part>> _pathsOf(
    List<CopiesFrame> frames,
    List<LevelCopies> levelCopies,
  ) {
    final paths = <String, List<_Part>>{};
    void add(CopiesNode node, Copy copy, int? chosenAt) {
      final name = (name: copyName(node, copy.number), chosenAt: chosenAt);
      for (final effect in copy.effects) {
        (paths[effect.effectId] ??= []).add(name);
      }
    }

    for (final frame in frames) {
      for (final copy in frame.copies) {
        add(
          frame.node,
          copy,
          copy.id == frame.selected?.id ? frame.depth : null,
        );
      }
    }
    for (final (:node, :copies) in levelCopies) {
      for (final copy in copies) {
        add(node, copy, null);
      }
    }
    return paths;
  }

  /// The copies chosen, `pkg 2 › target 1`; `null` when none is.
  String? get copy {
    final names = [
      for (final frame in frames)
        if (frame.selected case final copy?) frame.nameOf(copy),
    ];
    return names.isEmpty ? null : names.join(' › ');
  }

  /// The copies the effect [effectId] is in, those chosen too: `pkg 2 ›
  /// target 1`; `null` for an effect in none.
  String? copyOf(String effectId) => switch (_paths[effectId]) {
    final path? => [for (final part in path) part.name].join(' › '),
    null => null,
  };

  /// What a row of `Logs` says of the copies the effect [effectId] is in, but
  /// those chosen, which the title says — those chosen down to the level
  /// [upTo], when the title is of a level above: `pkg 2 › target 1`;
  /// `null` for an effect in none.
  String? tagOf(String effectId, {int? upTo}) {
    final names = [
      for (final part in _paths[effectId] ?? const <_Part>[])
        if (part.chosenAt == null || upTo != null && part.chosenAt! > upTo)
          part.name,
    ];
    return names.isEmpty ? null : names.join(' › ');
  }
}

/// The name of a copy an effect is in, and the depth of its frame when it is
/// the copy shown there.
typedef _Part = ({String name, int? chosenAt});

/// What [levels] show of [session]: each level opened from a `copies` node
/// is a frame with its copies, the copy [selected] at its depth (by the id
/// of its first effect) shown; the effects of the levels below are that copy's.
/// A selected copy the frame does not have shows all. The `copies` nodes of
/// the last level, which is drawn, have their copies too, and so do those
/// inside them: in the bodies of copies and of the functions calls call,
/// each numbered within the copy around it (`pkg 1 › target 2`).
///
/// Copies in copies are numbered within the copy of the frame around them;
/// while that frame shows all its copies, none of the inner ones can be
/// chosen.
ShownEffects framesOf(
  List<BodyLevel> levels, {
  required EffectPlaces places,
  required SessionData session,
  Map<int, String> selected = const {},
}) {
  var effects = session.state.effects;
  // The copies the next frame's copies are numbered within, with the frame
  // they are of; none when one copy or no frame holds the effects.
  ({CopiesNode node, List<Copy> copies})? around;
  List<Copy> copiesOf0(CopiesNode node) => [
    for (final group in around?.copies.map((copy) => copy.effects) ?? [effects])
      ...copiesOf(node, places: places, session: session, effects: group),
  ];

  final frames = <CopiesFrame>[];
  final chosen = <String>[];
  for (final (depth, level) in levels.indexed.skip(1)) {
    final node = levels[depth - 1].body.node(level.opened!.nodeId);
    if (node is! CopiesNode) continue;
    final copies = copiesOf0(node);
    final copy = around != null
        ? null
        : copies.where((copy) => copy.id == selected[depth]).firstOrNull;
    if (copy != null) chosen.add(copyName(node, copy.number));
    frames.add(
      CopiesFrame._(
        node: node,
        depth: depth,
        copies: copies,
        around: around?.node,
        selected: copy,
        footer: copy == null
            ? _progress(copies)
            : '${chosen.join(' › ')} · ${_now(copy, session)}',
      ),
    );
    if (copy != null) {
      effects = copy.effects;
      around = null;
    } else {
      around = (node: node, copies: copies);
    }
  }
  final body = levels.lastOrNull?.body;
  final levelCopies = body == null
      ? const <LevelCopies>[]
      : _levelCopies(
          body,
          around?.copies.map((copy) => copy.effects) ?? [effects],
          places: places,
          session: session,
        );
  return ShownEffects._(
    List.unmodifiable(frames),
    levelCopies,
    List.unmodifiable(effects),
  );
}

/// The copies of the `copies` nodes in [body], the level drawn, and inside
/// it — in the bodies of copies and of the functions calls call — the outer
/// before the inner; [groups] are the effects the level shows, by the copy of
/// the frame it is the body of.
///
/// Each node is there once, however many calls reach it: by place, its
/// copies gather its effects from every call. A node reached inside copies on
/// some way to it is numbered within the copy around it there, as copies in
/// copies are (decision 11: `pkg 1 › target 2`); a node reached only
/// outside copies, within [groups].
List<LevelCopies> _levelCopies(
  GraphBody body,
  Iterable<List<EffectState>> groups, {
  required EffectPlaces places,
  required SessionData session,
}) {
  // Each node reached, with the copies node around it — one around it on
  // some way to it, if any — in the order first reached.
  final around = LinkedHashMap<CopiesNode, CopiesNode?>.identity();
  // The functions walked, each once in each copies node around it (-1 for
  // none): a function many calls call is walked once.
  final indexes = Map<CopiesNode, int>.identity();
  final walked = <(String, int)>{};
  // Whether [node] is [within] or around it.
  bool holds(CopiesNode? within, CopiesNode node) {
    for (var outer = within; outer != null; outer = around[outer]) {
      if (identical(outer, node)) return true;
    }
    return false;
  }

  void walk(GraphBody body, CopiesNode? within, Set<String> entered) {
    for (final node in body.nodes) {
      switch (node) {
        case CopiesNode():
          final reached = around.containsKey(node);
          // Never the node itself, nor one inside it: a function that calls
          // itself from inside the node reaches the node again.
          if (!reached || around[node] == null && !holds(within, node)) {
            around[node] = within;
          }
          if (reached) continue;
          indexes[node] = indexes.length;
          walk(node.body, node, entered);
        case CallNode():
          final context = within == null ? -1 : indexes[within]!;
          for (final function in places.calledBy(node)) {
            // A function in [entered] calls itself: it holds nothing new.
            if (entered.contains(function.id)) continue;
            if (!walked.add((function.id, context))) continue;
            walk(function.body, within, {...entered, function.id});
          }
        case EffectNode() || ConditionNode():
      }
    }
  }

  // The function the level is the body of is entered: a call of it from
  // inside the level holds nothing new.
  walk(body, null, {?places.ownerOf(body)});
  final levelCopies = <LevelCopies>[];
  final copiesOfNode = Map<CopiesNode, List<Copy>>.identity();
  List<Copy> copiesAt(CopiesNode node) {
    if (copiesOfNode[node] case final copies?) return copies;
    copiesOfNode[node] = const []; // a node around itself holds no copies
    final outer = around[node];
    final within = outer == null
        ? groups
        : [for (final copy in copiesAt(outer)) copy.effects];
    final copies = [
      for (final group in within)
        ...copiesOf(node, places: places, session: session, effects: group),
    ];
    levelCopies.add((node: node, copies: copies));
    return copiesOfNode[node] = copies;
  }

  around.keys.forEach(copiesAt);
  return levelCopies;
}

/// `done 1 of 3`, `done 1 of 3 · 1 failed`.
String _progress(List<Copy> copies) {
  int count(CopyStatus status) =>
      copies.where((copy) => copy.status == status).length;
  final failed = count(CopyStatus.failed);
  return 'done ${count(CopyStatus.finished)} of ${copies.length}'
      '${failed == 0 ? '' : ' · $failed failed'}';
}

/// Where [copy] is: `now verify`, `done`, `failed at verify`,
/// `interrupted at verify`.
String _now(Copy copy, SessionData session) {
  String names(EffectStatus status) => {
    for (final effect in copy.effects)
      if (effect.status == status) ?session.effects[effect.effectId]?.name,
  }.join(', ');
  return switch (copy.status) {
    CopyStatus.running => 'now ${names(EffectStatus.running)}',
    CopyStatus.interrupted => 'interrupted at ${names(EffectStatus.running)}',
    CopyStatus.failed => 'failed at ${names(EffectStatus.failed)}',
    CopyStatus.finished => 'done',
  };
}

/// How the copy of [effects] stands; a running one is [interrupted] when the
/// process of its session is gone.
CopyStatus _statusOf(List<EffectState> effects, {required bool interrupted}) {
  if (effects.any((effect) => effect.status == EffectStatus.failed)) {
    return CopyStatus.failed;
  }
  if (effects.any((effect) => effect.status == EffectStatus.running)) {
    return interrupted ? CopyStatus.interrupted : CopyStatus.running;
  }
  return CopyStatus.finished;
}

/// The most characters of a hint: a longer one is cut, `…` at its end.
const hintLength = 24;

/// What the output [value] of a copy's first effect hints at it: a string as
/// it is, anything else as JSON, on one line, cut to [hintLength]
/// characters.
String copyHint(Object? value) {
  final text = (value is String ? value : jsonEncode(value)).replaceAll(
    RegExp(r'\s+'),
    ' ',
  );
  return text.length <= hintLength
      ? text
      : '${text.substring(0, hintLength - 1)}…';
}
