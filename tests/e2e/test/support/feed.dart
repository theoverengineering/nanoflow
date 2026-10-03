import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_reader/nanoflow_reader.dart';
import 'package:test/test.dart';

/// The feed of a reader, collected as it comes until the test ends.
final class Feed {
  Feed(this.reader) {
    final subscription = reader.changes().listen(
      changes.add,
      onError: errors.add,
    );
    addTearDown(subscription.cancel);
  }

  final FsReader reader;

  /// Every change given so far, in order.
  final List<Change> changes = [];

  /// Every error given so far.
  final List<Object> errors = [];

  /// The changes of the session [sessionId] given so far, in order.
  List<Change> of(String sessionId) => [
    for (final change in changes)
      if (sessionIdOf(change) == sessionId) change,
  ];

  /// Waits until the feed has given [change]; fails the test, with what the
  /// feed gave of its session, when it has not after 20 s.
  Future<void> given(Change change) =>
      givenWhere(sessionIdOf(change), '$change', (other) => other == change);

  /// Waits until the feed has given a change of the session [sessionId] that
  /// [matches]; fails the test, saying it waited for [what], with what the
  /// feed gave of that session, when it has not after 20 s.
  Future<void> givenWhere(
    String sessionId,
    String what,
    bool Function(Change change) matches,
  ) async {
    const tick = Duration(milliseconds: 50);
    final waited = Stopwatch()..start();
    while (!of(sessionId).any(matches)) {
      if (waited.elapsed > const Duration(seconds: 20)) {
        fail(
          'the feed has not given $what; of the session $sessionId it gave '
          '${of(sessionId)}',
        );
      }
      await Future<void>.delayed(tick);
    }
  }

  /// Waits until the feed has given nothing new for 300 ms — many scans of
  /// a reader that polls every few tens of milliseconds; fails the test when
  /// it has not settled after 20 s.
  Future<void> settle() async {
    var given = -1;
    var quiet = Duration.zero;
    const tick = Duration(milliseconds: 50);
    final waited = Stopwatch()..start();
    while (quiet < const Duration(milliseconds: 300)) {
      if (waited.elapsed > const Duration(seconds: 20)) {
        fail('the feed has not settled; it gave $changes');
      }
      await Future<void>.delayed(tick);
      final now = changes.length + errors.length;
      quiet = now == given ? quiet + tick : Duration.zero;
      given = now;
    }
  }
}

/// The id of the session [change] is of.
String sessionIdOf(Change change) => switch (change) {
  SessionAdded(:final session) => session.id,
  StepAdded(:final step) || StepChanged(:final step) => step.sessionId,
  EventAdded(:final sessionId) ||
  DocumentAdded(:final sessionId) ||
  LogCorrupted(:final sessionId) ||
  OwnerChanged(:final sessionId) => sessionId,
};
