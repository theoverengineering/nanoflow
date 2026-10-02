// The review graph from README «Формат», written as an ordinary function.
import 'package:static_graph/flow.dart';

class Request {
  Request(this.branch);
  final String branch;
}

class Change {
  Change(this.id, this.path);
  final String id;
  final String path;
}

class Report {
  Report(this.change, this.findings);
  final Change change;
  final List<String> findings;
}

Future<void> review(Flow f, Request r) async {
  var change = await f.step('collect', () => collect(r));
  if (change.path.isEmpty) {
    await f.step('discard', () => print('nothing to review'));
    return;
  }
  while (true) {
    final report = await f.step('inspect', () => inspect(change));
    if (report.findings.isEmpty) {
      await Future.wait([
        f.step('publish', () => print('published ${report.change.path}')),
        f.step('notify', () => print('${report.change.id}: accepted')),
      ]);
      return;
    }
    change = await f.step('fix', () => fix(report));
  }
}

Change collect(Request r) =>
    Change(r.branch, r.branch.isEmpty ? '' : 'lib/${r.branch}.dart');

Report inspect(Change c) => Report(c, [
  if (c.path.contains(RegExp('[A-Z]'))) '${c.path}: not lower_snake_case',
]);

Change fix(Report r) =>
    Change(r.change.id, r.change.path.replaceAll(RegExp('[A-Z]'), '_'));
