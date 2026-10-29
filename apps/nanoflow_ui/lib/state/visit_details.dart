/// What the effect details window shows of an effect: the effect among all the
/// visits to its node, how it went, when it started and ended, and its
/// place in the code; or, for a node without effects, the node's name and
/// place alone (docs/ui-spec.md «Окно деталей эффекта»; spec §9 «Окно
/// эффекта»). Pure: the time is passed in.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'effect_details.dart';
import 'effect_places.dart';
import 'session_feed.dart';
import 'texts.dart';
import 'visits.dart';

/// How the effect went, at the top of the window: `finished · 4m 02s`,
/// `running · 2m 14s`, `failed · 0.1s`; `interrupted` alone: when it would
/// have ended is not known.
typedef EffectResult = ({StartOutcome status, String text});

/// A start of the effect, as the window lists it: `14:09:20`, and how it
/// ended.
typedef StartText = ({String time, StartOutcome outcome});

/// The facts of the effect: `Started`, `Finished`, `Starts`.
final class EffectFacts {
  EffectFacts._({
    required this.started,
    required this.finished,
    required this.took,
    required List<StartText> starts,
  }) : starts = List.unmodifiable(starts);

  /// The first start, to the millisecond: `14:09:20.118`.
  final String started;

  /// The outcome of the last start, to the millisecond; `null` while the
  /// effect runs.
  final String? finished;

  /// `took 4m 02s`; `null` with [finished].
  final String? took;

  /// Every start, and how it ended.
  final List<StartText> starts;
}

/// The effect details window on an effect, or on a node without one.
final class VisitDetails {
  VisitDetails._({
    required this.name,
    required this.place,
    required this.doc,
    required List<Visit> visits,
    this.index,
    this.effect,
    this.result,
    this.facts,
  }) : visits = List.unmodifiable(visits);

  /// The effect's name, or the node's.
  final String name;

  /// Where the effect was called, or where the node is: `lib/review.dart:49`.
  final String? place;

  /// The doc of the effect's node (node docs design §4.2); `null` without
  /// one.
  final String? doc;

  /// Every visit to the effect's node among the effects shown, in order.
  final List<Visit> visits;

  /// Which of [visits] is shown; `null` for a node alone.
  final int? index;

  Visit? get visit => switch (index) {
    final i? => visits[i],
    null => null,
  };

  /// `Visit 2 of 2`.
  String? get visitText =>
      index == null ? null : 'Visit ${index! + 1} of ${visits.length}';

  /// The visit before, and the one after.
  Visit? get previous =>
      index != null && index! > 0 ? visits[index! - 1] : null;
  Visit? get next =>
      index != null && index! < visits.length - 1 ? visits[index! + 1] : null;

  /// The effect: its output, its error with the stack.
  final EffectDetails? effect;

  final EffectResult? result;

  final EffectFacts? facts;
}

/// The window on the effect [effectId] of [session] among [effects], the
/// effects shown, at [now]. Without the effect — for `Current graph`, or a
/// node without effects — the window shows the effect node [node] alone.
VisitDetails visitDetails({
  required SessionData? session,
  required Iterable<EffectState> effects,
  required EffectPlaces places,
  required String? effectId,
  EffectNode? node,
  required DateTime now,
}) {
  final details = session == null || effectId == null
      ? null
      : effectDetails(session, effectId);
  if (session == null || details == null) {
    return VisitDetails._(
      name: node?.name ?? '',
      place: node?.place,
      doc: node?.doc,
      visits: const [],
    );
  }
  final visits = visitsLike(session, effects, places, details.effectId);
  final index = visits.indexWhere(
    (visit) => visit.effectId == details.effectId,
  );
  final state = visits[index].state;
  final status = outcomeOf(session, state);
  // Not shown for an interrupted effect: when it would have ended is not
  // known.
  final took = formatDuration(
    (state.finishedAt ?? now).difference(state.startedAt),
  );
  return VisitDetails._(
    name: details.name,
    place: details.place,
    doc:
        node?.doc ??
        places
            .of(session.effects[details.effectId])
            .map((node) => node.doc)
            .nonNulls
            .firstOrNull,
    visits: visits,
    index: index,
    effect: details,
    result: (
      status: status,
      text: status == StartOutcome.interrupted
          ? status.name
          : '${status.name} · $took',
    ),
    facts: EffectFacts._(
      started: clockTimeMillis(state.startedAt),
      finished: state.finishedAt == null
          ? null
          : clockTimeMillis(state.finishedAt!),
      took: state.finishedAt == null ? null : 'took $took',
      starts: [
        for (final start in startsOf(session, details.effectId))
          (time: clockTime(start.at), outcome: start.outcome),
      ],
    ),
  );
}
