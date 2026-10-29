// Graphs whose routes decide by an `if` or a `?:` first: sizes and chained,
// by an else-if chain of each; returns, by `if`s with no else one after
// another; cases, by an if-case; nested, by a `?:` whose condition holds
// another.
import 'package:nanoflow/nanoflow.dart';

final class Draft {
  const Draft(this.text);
  final String text;
}

final read = node('read', (int n) async => n);
final small = node('small', (int n) async => n);
final big = node('big', (int n) async => n);
final huge = node('huge', (int n) async => n);
final write = node('write', (Draft draft) async => draft);
final skip = node('skip', (Draft draft) async => draft);

final sizes = Graph<int, int>('sizes', [
  Graph.start(read).next((n) {
    if (n < 10) {
      return small(n);
    } else if (n < 100) {
      return big(n);
    } else {
      return huge(n);
    }
  }),
]);

final chained = Graph<int, int>('chained', [
  Graph.start(read).next(
    (n) => n < 10
        ? small(n)
        : n < 100
        ? big(n)
        : huge(n),
  ),
]);

final returns = Graph<int, int>('returns', [
  Graph.start(read).next((n) {
    if (n < 10) return small(n);
    if (n < 100) return big(n);
    return null;
  }),
]);

final cases = Graph<Draft, Draft>('cases', [
  Graph.start(write).next((draft) {
    if (draft case Draft(text: '')) return skip(draft);
    return null;
  }),
]);

final nested = Graph<int, int>('nested', [
  Graph.start(read).next((n) => n < 10 ? (n < 5 ? small(n) : big(n)) : huge(n)),
]);
