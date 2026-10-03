/// The copies of a `copies` frame in a session (spec §9 «Копии», decisions
/// 10 and 11): the body run side by side, once for each item of a list.
///
/// A copy is a chain of the frame's steps by `after`: its first step is one
/// whose predecessor — the step whose key its record's `after` is — lies
/// outside the frame (a step at no place the frame holds, or none at all);
/// every other step of the frame belongs to the copy of its predecessor. A
/// rerun rewrites a record's `after`: the chain follows the record as it is
/// now. Copies are numbered by when they started. Pure.
library;

import 'dart:convert';

import 'package:nanoflow_model/nanoflow_model.dart';

import 'body_path.dart';
import 'session_feed.dart';
import 'step_places.dart';

/// How a copy stands, as its steps tell.
enum CopyStatus {
  /// A step of it runs.
  running,

  /// Its steps have finished.
  finished,

  /// A step of it failed: the last time it ran, it threw.
  failed,
}

/// One copy of a frame: its steps, and how it stands.
final class Copy {
  Copy._(this.number, this.first, List<StepState> steps, this.status)
    : steps = List.unmodifiable(steps),
      _ids = {for (final step in steps) step.stepId};

  /// From 1, in the order the copies started.
  final int number;

  /// The step that started the copy: its predecessor is outside the frame.
  final StepState first;

  /// The copy's steps in the order of their first `step-started`.
  final List<StepState> steps;

  final CopyStatus status;

  final Set<String> _ids;

  /// The copy's id: that of its [first] step.
  String get id => first.stepId;

  /// The document with the output of the [first] step, which hints at
  /// which copy it is (`core:uploaded`); `null` until that step finished.
  String? get hintDocument => first.outputId;

  /// Whether the step [stepId] is one of the copy's.
  bool contains(String stepId) => _ids.contains(stepId);
}

/// The copies of [frame] among [steps] of [session] (by default, all of its
/// steps): those at the places [places] says the frame holds, in chains by
/// `after`, numbered by the time of their first `step-started`. A step
/// whose record has not been given is in none.
List<Copy> copiesOf(
  CopiesNode frame, {
  required StepPlaces places,
  required SessionData session,
  Iterable<StepState>? steps,
}) {
  final held = places.within(frame);
  bool inside(Step? record) =>
      record != null && places.of(record.place).any(held.contains);

  // The first step of the copy of each step, by id: every step walked
  // gets it, so that each chain is walked once.
  final firsts = <String, String>{};
  String firstOf(Step record) {
    final walked = <String>{};
    var step = record;
    String first;
    while (true) {
      final known = firsts[step.id];
      if (known != null) {
        first = known;
        break;
      }
      walked.add(step.id);
      final after = step.after;
      final before = after == null ? null : session.stepWithKey(after);
      if (before == null || !inside(before) || walked.contains(before.id)) {
        first = step.id;
        break;
      }
      step = before;
    }
    for (final id in walked) {
      firsts[id] = first;
    }
    return first;
  }

  final states = {for (final step in session.state.steps) step.stepId: step};
  final chains = <String, List<StepState>>{};
  for (final step in steps ?? session.state.steps) {
    final record = session.steps[step.stepId];
    if (!inside(record)) continue;
    (chains[firstOf(record!)] ??= []).add(step);
  }
  final started = [
    for (final MapEntry(key: first, value: chain) in chains.entries)
      (
        first: states[first] ?? chain.first,
        chain: chain,
        at: chain
            .map((step) => step.startedAt)
            .reduce((a, b) => b.isBefore(a) ? b : a),
      ),
  ];
  // A stable sort: copies that started together keep the order of their
  // steps.
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
        _statusOf(started[i].chain),
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

  /// The copies among the steps shown, each numbered within the copy of
  /// the frame around it.
  final List<Copy> copies;

  /// The frame around this one that shows all its copies, so that none of
  /// this one's can be chosen; `null` when one can.
  final CopiesNode? around;

  /// The copy shown; `null` for all.
  final Copy? selected;

  /// Under the frame: `done 1 of 3` for all; `pkg 2 · now verify` for one.
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

/// The copies of a `copies` node of the level drawn, which is not opened:
/// they name the steps in them.
typedef LevelCopies = ({CopiesNode node, List<Copy> copies});

/// What the levels of the canvas show of a session: the copies frames they
/// go down through, and the steps shown — those of the copy selected in
/// each frame, all steps when none is.
final class ShownSteps {
  ShownSteps._(this.frames, this.levelCopies, this.steps)
    : _paths = _pathsOf(frames, levelCopies);

  final List<CopiesFrame> frames;

  /// The copies of the `copies` nodes of the level drawn.
  final List<LevelCopies> levelCopies;

  /// The steps shown, in the order of their first `step-started`.
  final List<StepState> steps;

  /// The names of the copies each step is in, frame by frame, with the
  /// depth of the frame where it is the copy shown; `null` for any other.
  final Map<String, List<_Part>> _paths;

  static Map<String, List<_Part>> _pathsOf(
    List<CopiesFrame> frames,
    List<LevelCopies> levelCopies,
  ) {
    final paths = <String, List<_Part>>{};
    void add(CopiesNode node, Copy copy, int? chosenAt) {
      final name = (name: copyName(node, copy.number), chosenAt: chosenAt);
      for (final step in copy.steps) {
        (paths[step.stepId] ??= []).add(name);
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

  /// The copies the step [stepId] is in, those chosen too: `pkg 2 ›
  /// target 1`; `null` for a step in none.
  String? copyOf(String stepId) => switch (_paths[stepId]) {
    final path? => [for (final part in path) part.name].join(' › '),
    null => null,
  };

  /// What a row of `Logs` says of the copies the step [stepId] is in, but
  /// those chosen, which the title says — those chosen down to the level
  /// [upTo], when the title is of a level above: `pkg 2 › target 1`;
  /// `null` for a step in none.
  String? tagOf(String stepId, {int? upTo}) {
    final names = [
      for (final part in _paths[stepId] ?? const <_Part>[])
        if (part.chosenAt == null || upTo != null && part.chosenAt! > upTo)
          part.name,
    ];
    return names.isEmpty ? null : names.join(' › ');
  }
}

/// The name of a copy a step is in, and the depth of its frame when it is
/// the copy shown there.
typedef _Part = ({String name, int? chosenAt});

/// What [levels] show of [session]: each level opened from a `copies` node
/// is a frame with its copies, the copy [selected] at its depth (by the id
/// of its first step) shown; the steps of the levels below are that copy's.
/// A selected copy the frame does not have shows all. The `copies` nodes of
/// the last level, which is drawn, have their copies too.
///
/// Copies in copies are numbered within the copy of the frame around them;
/// while that frame shows all its copies, none of the inner ones can be
/// chosen.
ShownSteps framesOf(
  List<BodyLevel> levels, {
  required StepPlaces places,
  required SessionData session,
  Map<int, String> selected = const {},
}) {
  var steps = session.state.steps;
  // The copies the next frame's copies are numbered within, with the frame
  // they are of; none when one copy or no frame holds the steps.
  ({CopiesNode node, List<Copy> copies})? around;
  List<Copy> copiesOf0(CopiesNode node) => [
    for (final group in around?.copies.map((copy) => copy.steps) ?? [steps])
      ...copiesOf(node, places: places, session: session, steps: group),
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
      steps = copy.steps;
      around = null;
    } else {
      around = (node: node, copies: copies);
    }
  }
  return ShownSteps._(List.unmodifiable(frames), [
    if (levels.lastOrNull?.body case final body?)
      for (final node in body.nodes.whereType<CopiesNode>())
        (node: node, copies: copiesOf0(node)),
  ], List.unmodifiable(steps));
}

/// `done 1 of 3`, `done 1 of 3 · 1 failed`.
String _progress(List<Copy> copies) {
  int count(CopyStatus status) =>
      copies.where((copy) => copy.status == status).length;
  final failed = count(CopyStatus.failed);
  return 'done ${count(CopyStatus.finished)} of ${copies.length}'
      '${failed == 0 ? '' : ' · $failed failed'}';
}

/// Where [copy] is: `now verify`, `done`, `failed at verify`.
String _now(Copy copy, SessionData session) {
  String names(StepStatus status) => {
    for (final step in copy.steps)
      if (step.status == status) ?session.steps[step.stepId]?.name,
  }.join(', ');
  return switch (copy.status) {
    CopyStatus.running => 'now ${names(StepStatus.running)}',
    CopyStatus.failed => 'failed at ${names(StepStatus.failed)}',
    CopyStatus.finished => 'done',
  };
}

CopyStatus _statusOf(List<StepState> steps) {
  if (steps.any((step) => step.status == StepStatus.failed)) {
    return CopyStatus.failed;
  }
  return steps.any((step) => step.status == StepStatus.running)
      ? CopyStatus.running
      : CopyStatus.finished;
}

/// The most characters of a hint: a longer one is cut, `…` at its end.
const hintLength = 24;

/// What the output [value] of a copy's first step hints at it: a string as
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
