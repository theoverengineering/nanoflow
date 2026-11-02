// A route for a failed call (failure route design): a part of a graph may
// say what follows when the call of its node fails — its node's effect
// threw, or a node or a route of its graph threw and nothing in it caught
// that. The failure route gets the call's input and the failure, as the
// journal keeps it, and the failure fails neither the branch nor the
// session.
//
// A caught failure is final: an effect whose failure a route catches — of
// the node called, or of any node of the graph called, at any depth — does
// not run again on resume; its `effect-failed` is its outcome, and it fails
// again with the same text and type. Routes are pure, and throw again: so a
// graph fails again with the same failure, and its failure route replays.
//
// A call with a failure route gives its failure as a value, [Caught], and
// not as an exception: its branch goes on where it would after its output,
// in the context it would, and registers no callback it would not without
// the route. So the keys of the effects round it are those without it.

/// A call that failed, as its failure route gets it: what the node threw, or
/// what a node or a route of the graph threw that nothing in it caught.
///
/// Only the text and the type: the journal keeps nothing else, and on resume
/// the route gets what it got before.
final class CallFailure {
  const CallFailure(this.error, {this.type});

  /// The exception's text on one line, as `effect-failed` keeps it: its
  /// `toString()`, each run of line breaks a space.
  final String error;

  /// The name of the exception's type, `StateError`; `null` when the journal
  /// has none: the failure was written before nanoflow kept it.
  final String? type;

  @override
  bool operator ==(Object other) =>
      other is CallFailure && other.error == error && other.type == type;

  @override
  int get hashCode => Object.hash(error, type);

  @override
  String toString() => 'CallFailure(${type == null ? '' : '$type: '}$error)';
}

/// What a failure of a call, or of an effect or a run in it, comes to.
enum Failures {
  /// No failure route catches it: it is thrown, as it comes, and an effect
  /// that failed runs again on resume.
  thrown,

  /// The failure route of a call round it catches it: it is final — an
  /// effect that failed does not run again on resume, and fails again with
  /// its saved text and type — and thrown, to that call; of the failures
  /// of the branches of a run, the first in the graph's order.
  kept,

  /// The call's own failure route catches it: final, as [kept], and given
  /// as a [Caught] instead of an output.
  caught,
}

/// The failure a call with a failure route gives instead of its output.
final class Caught {
  const Caught(this.failure);

  final CallFailure failure;
}

/// What an effect from the journal fails with, in a run whose failure a
/// failure route catches: the failure it failed with before.
final class ReplayedFailure implements Exception {
  const ReplayedFailure(this.failure);

  final CallFailure failure;

  /// The text of the failure it replays, as that failure's own was.
  @override
  String toString() => failure.error;
}

/// The failure [error] is, as the journal keeps it: its text on one line
/// and the name of its type; for a [ReplayedFailure], the saved ones.
CallFailure failureOf(Object error) => switch (error) {
  ReplayedFailure(:final failure) => failure,
  _ => CallFailure(errorText(error), type: '${error.runtimeType}'),
};

/// The text of [error] on one line: every run of line breaks is a space.
String errorText(Object error) => '$error'.replaceAll(RegExp(r'[\r\n]+'), ' ');
