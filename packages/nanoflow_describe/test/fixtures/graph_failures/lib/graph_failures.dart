// Failure routes: `.failed(…)` of a node or of a graph that is a node, after
// `.next(…)` or before it, is drawn from the node as edges labelled `failed`
// and marked `failed: true`; its first `switch` is a fork of its own, not
// exits of the node, which are its route's; a `for` element and a limit mark
// its edges as in a route, and `null` leads to the end. A join has none.
import 'package:nanoflow/nanoflow.dart';

final ids = node('ids', (List<int> ids) async => ids);
final claim = node('claim', (int i) async => i);
final develop = node('develop', (int i) async => i);
final settle = node('settle', (int i) async => i);
final giveBack = node('giveBack', (int i) async => i);
final retry = node('retry', (int i) async => i);

final developIdea = Graph<int, int>('developIdea', [Graph.start(develop)]);

/// One idea of a night: what fails in its development is given back.
final nightIdea = Graph<int, int>('nightIdea', [
  Graph.start(claim).next((i) => developIdea(i)),
  Graph.part(developIdea)
      .next((i) => settle(i))
      .failed((i, failure) => giveBack(i)),
]);

/// A failure route before the route, which decides by the type first.
final picky = Graph<int, Object?>('picky', [
  Graph.start(claim)
      .failed(
        (i, failure) => switch (failure.type) {
          'StateError' => retry(i),
          _ => null,
        },
      )
      .next((i) => i > 0 ? settle(i) : giveBack(i)),
]);

/// A failure route of copies, a few at a time; a node without a route of
/// its own ends its branch.
final batch = Graph<List<int>, Object?>('batch', [
  Graph.start(ids).next((ids) => {for (final i in ids) develop(i)}),
  Graph.part(develop).failed(
    (i, failure) => {
      for (final r in [i, -i]) retry(r, limit: 2),
    },
  ),
]);

/// A failure route of a join, which calls nothing: not drawn.
final joined = Graph<int, Object?>('joined', [
  Graph.start(claim).next((i) => {settle(i), retry(i)}),
  Graph.join([settle, retry]).failed((Object? both, failure) => null),
]);
