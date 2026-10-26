// Graphs whose routes run a node once per item, side by side: fan, by a
// `for … in` element after a ?:, and count, by a `for (…)` element next to
// a node of its own; a `for` element whose body is no node is not drawn.
import 'package:nanoflow/nanoflow.dart';

final split = node('split', (int n) async => [for (var i = 0; i < n; i++) i]);
final work = node('work', (int x) async => x * 2);
final first = node('first', (int x) async => x);
final skip = node('skip', (int x) async => x);

final fan = Graph<int, int>('fan', [
  Graph.start(split).next(
    (items) => items.isEmpty ? null : {for (final item in items) work(item)},
  ),
]);

final count = Graph<int, int>('count', [
  Graph.start(first).next(
    (n) => {
      skip(n),
      for (var i = 0; i < n; i++) work(i),
      for (final i in [n])
        if (i > 0) work(i),
    },
  ),
]);
