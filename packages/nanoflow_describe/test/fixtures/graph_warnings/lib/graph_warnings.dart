// Graphs that are drawn with warnings: what their arrows carry is not what
// their targets take, a key never matches, and what is not drawn at all.
import 'package:nanoflow/nanoflow.dart';

final class Change {
  Change(this.path);

  final String path;
}

final class Report {
  Report(this.path);

  final String path;
}

enum Verdict { pass, fail }

final class Square {}

Future<Change> begin(String branch) async => Change(branch);

Future<Report> check(Change change) async => Report(change.path);

Future<String> needsChange(Change change) async => change.path;

Future<Verdict> judge(Report report) async => Verdict.pass;

Future<String> done(Verdict verdict) async => '$verdict';

Future<String> left(Report report) async => report.path;

Future<int> right(Report report) async => 1;

Future<void> both((String, String) parts) async {}

final mismatched = Graph<String, void>('mismatched', [
  Graph.start(begin).next(check),
  Graph.part(check).next({needsChange, judge, left, right}),
  Graph.part(judge).next({Square: done, 'pass': done}),
  Graph.join([left, right]).next(both),
]);

const graphName = 'named';

final named = Graph<String, void>(graphName, [Graph.start(begin)]);

Graph<String, void> local() => Graph('local', [Graph.start(begin)]);

final aPart = Graph.start(begin);

final indirect = Graph<String, void>('indirect', [aPart]);

final closure = Graph<String, String>('closure', [
  Graph.start((String text) async => text),
]);

Future<void> twin(Flow f, String branch) async {
  await f.effect('locate', () => branch);
}

final twinGraph = Graph<String, void>('twin', [Graph.start(begin)]);
