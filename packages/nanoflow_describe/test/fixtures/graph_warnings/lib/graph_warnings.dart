// Graphs that are drawn with warnings: a node or a graph outside a top-level
// variable, names that are not literals or are taken, routes and values that
// cannot be read, a node no way reaches, a join whose route takes another
// record, a side effect in a route, graphs that are nodes and can end in
// several ends at once, parts that cannot be read, async or generator routes.
import 'package:nanoflow/nanoflow.dart';

final class Change {
  Change(this.path);

  final String path;
}

final class Report {
  Report(this.path);

  final String path;
}

final begin = node('begin', (String branch) async => Change(branch));

final check = node('check', (Change change) async => Report(change.path));

final recheck = node('check', (Change change) async => Report(change.path));

final done = node('done', (Report report) async => report.path);

final left = node('left', (Report report) async => report.path);

final right = node('right', (Report report) async => 1);

Node<String, String> local() => node('local', (String text) async => text);

Graph<String, void> localGraph() => Graph('localGraph', [Graph.start(begin)]);

const nodeName = 'aNode';

final named = node(nodeName, (String text) async => text);

const graphName = 'aGraph';

final namedGraph = Graph<String, void>(graphName, [Graph.start(named)]);

final twins = Graph<String, void>('twins', [
  Graph.start(begin).next((change) => check(change)),
  Graph.part(check).next((report) => recheck(Change(report.path))),
]);

final unread = Graph<String, void>('unread', [
  // ignore: implicit_call_tearoffs
  Graph.start(begin).next(check),
  Graph.part(check).next((report) => [done(report)]),
]);

final orphaned = Graph<String, void>('orphaned', [
  Graph.start(begin).next((change) => check(change)),
  Graph.part(left).next((path) => null),
]);

final joined = Graph<String, void>('joined', [
  Graph.start(begin).next((change) => check(change)),
  Graph.part(check).next((report) => {left(report), right(report)}),
  Graph.join([left, right]).next(((String, String) both) => null),
]);

final timed = Graph<String, void>('timed', [
  Graph.start(begin)
      .next((change) => DateTime.now().hour < 12 ? check(change) : null),
]);

final fanned = Graph<Report, String>('fanned', [
  Graph.start(done).next((path) => {left(Report(path)), right(Report(path))}),
]);

final started = Graph<Report, String>('started', [
  Graph.start(left),
  Graph.start(right),
]);

final outer = Graph<String, void>('outer', [
  Graph.start(begin).next((change) => check(change)),
  Graph.part(check)
      .next((report) => {fanned(report), started(report), joined(report.path)}),
]);

final aPart = Graph.start(begin);

final indirect = Graph<String, void>('indirect', [aPart]);

Future<void> twin(Flow f, String branch) async {
  await f.effect('locate', () => branch);
}

final twinGraph = Graph<String, void>('twin', [Graph.start(begin)]);

final awaited = Graph<String, void>('awaited', [
  Graph.start(begin).next((change) async => check(change)),
  Graph.part(check).next((report) sync* {
    yield done(report);
  }),
]);
