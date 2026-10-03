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

  /// Waits until the feed has given [change]; fails the test, with what the
  /// feed gave, when it has not after 20 s.
  Future<void> given(Change change) async {
    const tick = Duration(milliseconds: 50);
    final waited = Stopwatch()..start();
    while (!changes.contains(change)) {
      if (waited.elapsed > const Duration(seconds: 20)) {
        fail('the feed has not given $change; it gave $changes');
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
