// Calls with a limit of copies at once: the limit, as written, goes to the
// edge of the call — of a graph or a node, in a `for` element or not, a
// literal or computed —; a call without one has none.
import 'package:nanoflow/nanoflow.dart';

final class Night {
  Night(this.ideas, this.parallel);

  final List<int> ideas;
  final int parallel;
}

final plan = node('plan', (int n) async => Night([n], 2));
final develop = node('develop', (int idea) async => idea);
final report = node('report', (int idea) async => idea);
final sum = node('sum', (int idea) async => idea);

final idea = Graph<int, int>('idea', [Graph.start(develop)]);

final night = Graph<int, int>('night', [
  Graph.start(plan).next(
    (night) => {
      for (final i in night.ideas) idea(i, limit: night.parallel),
      for (final i in night.ideas) report.call(i, limit: 2),
    },
  ),
  Graph.part(idea).next((i) => sum(i, limit: 1)),
  Graph.part(report).next((i) => sum(i)),
]);

/// Calls sum with a limit of 2 either way: one arrow, with the limit.
final either = Graph<int, int>('either', [
  Graph.start(develop).next((i) => i > 0 ? sum(i, limit: 2) : sum(i, limit: 2)),
]);

/// Calls sum with a limit of 2 or without one: an exit for each.
final eitherOr = Graph<int, int>('eitherOr', [
  Graph.start(develop).next((i) => i > 0 ? sum(i, limit: 2) : sum(i)),
]);
