/// What the details of an effect show: which effect it is, where in the code it
/// was called, its output document and, for an effect that failed, its error
/// with the stack (docs/ui-spec.md «Logs»: «Детали эффекта»; spec §9 «Окно
/// эффекта»). An effect has no input: it takes its data from its closure. Pure.
library;

import 'package:nanoflow_model/nanoflow_model.dart';

import 'session_feed.dart';
import 'visits.dart' show StartOutcome, outcomeOf;

/// Whether an effect has its output.
enum DocumentState {
  /// Not there yet: the effect is running, or was interrupted.
  notYet,

  /// The effect has none: it failed, or finished without naming one.
  missing,

  /// The document [EffectDocument.documentId] holds it.
  present,
}

/// An effect's output.
final class EffectDocument {
  const EffectDocument._(this.state, {this.documentId, this.message});

  final DocumentState state;

  /// The document; `null` unless [state] is [DocumentState.present].
  final String? documentId;

  /// What the tab says instead of a document.
  final String? message;
}

/// An effect as its details show it.
final class EffectDetails {
  const EffectDetails._({
    required this.sessionId,
    required this.effectId,
    required this.name,
    required this.place,
    required this.status,
    required this.output,
    required this.error,
    required this.stack,
  });

  final String sessionId;

  final String effectId;

  /// The name given to `f.effect`.
  final String name;

  /// Where `f.effect` was called: `lib/review.dart:49`; `null` when not
  /// known.
  final String? place;

  /// How its last start stands: interrupted when the process of its
  /// session went while it ran.
  final StartOutcome status;

  bool get running => status == StartOutcome.running;

  final EffectDocument output;

  /// The error of the effect's last `effect-failed`, while it is failed.
  final String? error;

  /// The stack of that `effect-failed`.
  final String? stack;
}

/// The effect [effectId] of [session]; `null` until it has started and its
/// record has been read.
EffectDetails? effectDetails(SessionData session, String effectId) {
  final record = session.effects[effectId];
  final state = session.state.effects
      .where((effect) => effect.effectId == effectId)
      .firstOrNull;
  if (record == null || state == null) return null;
  final failure = state.status == EffectStatus.failed
      ? session.events.whereType<EffectFailed>().lastWhere(
          (event) => event.effectId == effectId,
        )
      : null;
  final status = outcomeOf(session, state);
  return EffectDetails._(
    sessionId: session.id,
    effectId: effectId,
    name: record.name,
    place: record.place,
    status: status,
    output: _output(status, state.outputId),
    error: failure?.error,
    stack: failure?.stack,
  );
}

/// `effect-finished` names the output, [outputId], before `effect.json` does.
EffectDocument _output(StartOutcome status, String? outputId) =>
    switch (status) {
      StartOutcome.running => const EffectDocument._(
        DocumentState.notYet,
        message: 'Not yet: the effect is still running',
      ),
      StartOutcome.interrupted => const EffectDocument._(
        DocumentState.notYet,
        message: 'Not yet: the effect was interrupted — the process stopped',
      ),
      StartOutcome.failed => const EffectDocument._(
        DocumentState.missing,
        message: 'No output: the effect failed',
      ),
      StartOutcome.finished => switch (outputId) {
        final id? => EffectDocument._(DocumentState.present, documentId: id),
        null => const EffectDocument._(
          DocumentState.missing,
          message: 'The effect gave no output',
        ),
      },
    };
