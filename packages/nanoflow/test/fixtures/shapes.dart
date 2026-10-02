// Graphs of every shape the library describes, built on the review graph.
import 'package:nanoflow/nanoflow.dart';

import 'review_graph.dart';

enum Verdict { accepted, returned }

final grade = fork(
  (Report r) async => r.findings.isEmpty ? Verdict.accepted : Verdict.returned,
);
final size = fork((Report r) => r.findings.length);
final empty = fork((Change c) => c.path.isEmpty);
final anything = node((Object? x) async {});
final whatever = node((dynamic x) => x);
final batch = node(
  (List<Change> changes) => {for (final c in changes) c.path: c.id.length},
);
final tally = node((Map<String, int> counts) => counts.values.toList());
final weigh = node((double w) => w > 1);
final label = node((bool heavy) => heavy ? 'heavy' : 'light');
final measure = node((String s) => s.length);
final scale = node((num n) => n > 0 ? Verdict.accepted : Verdict.returned);
final announce = node((Verdict v) {});

/// Nodes whose functions never return, so that Dart infers their result as
/// `Never`: one always throws, one waits for ever.
final rejects = node(
  (Report r) async => throw StateError('rejected ${r.change.path}'),
);
final waits = node((Object? _) async {
  while (true) {
    await Future<void>.delayed(const Duration(seconds: 1));
  }
});

/// One part is a graph too: it is not wrapped in `Graph([…])`.
final single = Graph.start(inspect).next(verdict).then({'accepted': publish});

/// Two starts; nodes come from two libraries and are used out of order.
final twoStarts = Graph([
  Graph.start(tally).next(anything),
  Graph.start(collect),
]);

/// A start fork whose outcomes are spread over two parts, each begun with
/// `Graph.start`.
final startTwice = Graph([
  Graph.start(grade).then({Verdict.accepted: publish}),
  Graph.start(grade).then({Verdict.returned: notify}),
]);

/// A start node with no `in`.
final noInput = Graph.start(anything);

/// Sets in set order, empty sets, and a switch spread over two parts.
final sets = Graph([
  Graph.start(inspect).next(grade).then({Verdict.accepted: publish}),
  Graph.part(grade)
      .then({
        Verdict.returned: {notify, publish},
      })
      .otherwise(<Vertex<void Function(Report), Object?>>{}),
  Graph.part(publish).next(<Vertex<void Function(Null), Object?>>{}),
]);

/// Sets of one node: as a worker's next, as an if's then and else, and as a
/// switch's target.
final oneNodeSets = Graph([
  Graph.start(collect).next({isEmpty}),
  Graph.part(isEmpty).then({discard}).otherwise({inspect}),
  Graph.part(inspect).next(grade).then({
    Verdict.accepted: {publish},
  }),
]);

/// Nodes that never return.
final neverReturns = Graph.start(inspect).next({rejects, waits});

/// A switch on numbers, with an `else`.
final numbers = Graph.start(size).then({0: publish, 2: notify}).otherwise(fix);

/// An if without `then`.
final onlyOtherwise = Graph.start(empty).otherwise(discard);

/// Every kind of data type.
final typed = Graph([
  Graph.start(batch).next(tally).next(anything).next(whatever),
  Graph.start(weigh).next(label).next(measure).next(scale).next(announce),
]);
