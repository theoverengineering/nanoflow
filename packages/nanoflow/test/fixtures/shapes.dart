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

/// One part is a graph too: it is not wrapped in `Graph([…])`.
final single = Graph.start(inspect).next(verdict).then({'accepted': publish});

/// Two starts; nodes come from two libraries and are used out of order.
final twoStarts = Graph([
  Graph.start(tally).next(anything),
  Graph.start(collect),
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

/// A switch on numbers, with an `else`.
final numbers = Graph.start(size).then({0: publish, 2: notify}).otherwise(fix);

/// An if without `then`.
final onlyOtherwise = Graph.start(empty).otherwise(discard);

/// Every kind of data type.
final typed = Graph([
  Graph.start(batch).next(tally).next(anything).next(whatever),
  Graph.start(weigh).next(label).next(measure).next(scale).next(announce),
]);
