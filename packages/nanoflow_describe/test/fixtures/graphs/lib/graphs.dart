// Graphs of nodes beside workflow functions: the review graph with Exits, a
// set and a join; maps that cover every value and maps that do not; graphs
// and workflow functions as nodes; a workflow function that calls a graph.
import 'package:nanoflow/nanoflow.dart';

final class Change {
  Change(this.path);

  final String path;
}

final class Report {
  Report(this.path, this.findings);

  final String path;
  final int findings;
}

sealed class Collected {}

final class Empty extends Exit<void> implements Collected {
  Empty() : super(null);
}

final class Found extends Exit<Change> implements Collected {
  Found(super.value);
}

sealed class Inspected {}

final class Clean extends Exit<Report> implements Inspected {
  Clean(super.value);
}

final class Findings extends Exit<Report> implements Inspected {
  Findings(super.value);
}

enum Verdict { pass, fail }

Future<Collected> collect(String branch) async =>
    branch.isEmpty ? Empty() : Found(Change(branch));

Future<Inspected> inspect(Change change) async => change.path.endsWith('!')
    ? Clean(Report(change.path, 0))
    : Findings(Report(change.path, 1));

Future<Change> fix(Report report) async => Change('${report.path}!');

Future<void> discard(void _) async {}

Future<String> publish(Report report) async => report.path;

Future<String> notify(Report report) async => report.path;

Future<void> report((String, String) sent) async {}

final review = Graph<String, void>('review', [
  Graph.start(collect).next({Empty: discard, Found: inspect}),
  Graph.part(inspect).next({
    Clean: {publish, notify},
    Findings: fix,
  }),
  Graph.part(fix).next(inspect),
  Graph.join([publish, notify]).next(report),
]);

/// A workflow function as a node.
Future<Change> prepare(Flow f, String branch) async {
  final path = await f.effect('locate', () => 'lib/$branch.dart');
  return Change(path);
}

/// A workflow function without effects as a node.
Future<String> plain(Flow f, Change change) async => change.path;

Future<(Verdict, Report)> judge(Change change) async =>
    (Verdict.pass, Report(change.path, 0));

Future<String> accept(Report report) async => report.path;

Future<bool> isLong(String text) async => text.length > 3;

Future<String> long(bool yes) async => 'long';

Future<String> retry(bool yes) async => 'retry';

final judged = Graph<String, String>('judged', [
  Graph.start(prepare).next(judge),
  Graph.part(judge).next({Verdict.pass: accept}),
]);

final measured = Graph<String, String>('measured', [
  Graph.start(isLong).next({true: long}, otherwise: retry),
]);

final nested = Graph<String, String>('nested', [
  Graph.start(judged).next(measured),
]);

final plainly = Graph<String, String>('plainly', [
  Graph.start(prepare).next(plain),
]);

Future<String> callsGraph(Flow f, String branch) async {
  final checked = await f.effect('check', () => branch);
  return nested(f, checked);
}

final viaCall = Graph<String, String>('viaCall', [Graph.start(judged.call)]);
