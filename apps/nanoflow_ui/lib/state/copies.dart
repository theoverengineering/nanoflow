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

  // The first step of the copy of each step, by id.
  final firsts = <String, String>{};
  String firstOf(Step record) {
    final seen = <String>{};
    var step = record;
    while (true) {
      final known = firsts[step.id];
      if (known != null) return known;
      final after = step.after;
      final before = after == null ? null : session.stepWithKey(after);
      if (before == null || !inside(before) || !seen.add(step.id)) break;
      step = before;
    }
    return firsts[record.id] = step.id;
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

/// A `copies` frame the canvas goes down through: a level opened from a
/// `copies` node, with the copies of it the session ran and the one
/// selected (decision 11).
final class CopiesFrame {
  CopiesFrame._({
    required this.node,
    required this.depth,
    required List<Copy> copies,
    required this.selected,
    required this.footer,
  }) : copies = List.unmodifiable(copies);

  final CopiesNode node;

  /// The level the frame's body is: its index among the canvas's levels.
  final int depth;

  /// The copies, numbered; within the copy selected in the frame around
  /// this one, if any.
  final List<Copy> copies;

  /// The copy shown; `null` for all of them.
  final Copy? selected;

  /// Under the frame: `done 1 of 3` for all; `copy 2 · now verify` for one.
  final String footer;

  /// Over the frame: `each pkg in packages`.
  String get title => 'each ${node.label}';

  /// Across from the [title]: `×3 · in parallel`.
  String get countText => '×${copies.length} · in parallel';
}

/// What the levels of the canvas show of a session: the copies frames they
/// go down through, and the steps shown — those of the copy selected in
/// each frame, all steps when none is.
final class ShownSteps {
  ShownSteps._(this.frames, this.steps, this.copyNumbers);

  final List<CopiesFrame> frames;

  /// The steps shown, in the order of their first `step-started`.
  final List<StepState> steps;

  /// The number of the copy each step is in, by step id, in the innermost
  /// frame while it shows all its copies; empty otherwise.
  final Map<String, int> copyNumbers;

  /// The copies selected, `copy 2 › copy 1`; `null` when none is.
  String? get copy => _path([
    for (final frame in frames)
      if (frame.selected case final copy?) copy.number,
  ]);

  /// The copies of the frames the step [stepId] is in: `copy 2 › copy 1`;
  /// `null` for a step in none.
  String? copyOf(String stepId) => _path([
    for (final frame in frames)
      for (final copy in frame.copies)
        if (copy.contains(stepId)) copy.number,
  ]);
}

String? _path(List<int> numbers) =>
    numbers.isEmpty ? null : numbers.map((n) => 'copy $n').join(' › ');

/// What [levels] show of [session]: each level opened from a `copies` node
/// is a frame with its copies, the copy [selected] at its depth (by the id
/// of its first step) shown; the steps of the levels below are that copy's.
/// A selected copy the frame does not have shows all.
ShownSteps framesOf(
  List<BodyLevel> levels, {
  required StepPlaces places,
  required SessionData session,
  Map<int, String> selected = const {},
}) {
  var steps = session.state.steps;
  final frames = <CopiesFrame>[];
  final chosen = <int>[];
  for (final (depth, level) in levels.indexed.skip(1)) {
    final node = levels[depth - 1].body.node(level.opened!.nodeId);
    if (node is! CopiesNode) continue;
    final copies = copiesOf(
      node,
      places: places,
      session: session,
      steps: steps,
    );
    final copy = copies.where((copy) => copy.id == selected[depth]).firstOrNull;
    if (copy != null) {
      chosen.add(copy.number);
      steps = copy.steps;
    }
    frames.add(
      CopiesFrame._(
        node: node,
        depth: depth,
        copies: copies,
        selected: copy,
        footer: copy == null
            ? _progress(copies)
            : '${_path(chosen)} · ${_now(copy, session)}',
      ),
    );
  }
  final last = frames.lastOrNull;
  return ShownSteps._(
    List.unmodifiable(frames),
    List.unmodifiable(steps),
    last == null || last.selected != null
        ? const {}
        : {
            for (final copy in last.copies)
              for (final step in copy.steps) step.stepId: copy.number,
          },
  );
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
