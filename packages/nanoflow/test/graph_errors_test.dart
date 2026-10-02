// A test of a graph as a user writes one: it imports the graph and only the
// public library.
import 'package:nanoflow/nanoflow.dart';
import 'package:test/test.dart';

import 'fixtures/build_errors.dart' as errors;
import 'fixtures/review_graph.dart' as review;

void main() {
  test('graphErrors is empty for a graph that builds', () {
    expect(graphErrors(review.graph), isEmpty);
  });

  test('graphErrors gives what --graph prints for a graph that does not '
      'build, one line per problem', () {
    expect(graphErrors(errors.severalErrors), [
      'graph has no Graph.start',
      'first: next is declared twice',
    ]);
  });
}
