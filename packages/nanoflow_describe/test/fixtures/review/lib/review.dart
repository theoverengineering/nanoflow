// The review graph from the README, written as an ordinary workflow
// function: a fork that ends the session, a loop that fixes the change until
// the inspection finds nothing, and two steps side by side.
import 'package:nanoflow/nanoflow.dart';

class Change {
  Change(this.id, this.path);

  factory Change.fromJson(Map<String, Object?> json) =>
      Change(json['id']! as String, json['path']! as String);

  final String id;
  final String path;

  Map<String, Object?> toJson() => {'id': id, 'path': path};
}

class Report {
  Report(this.change, this.findings);

  factory Report.fromJson(Map<String, Object?> json) => Report(
    Change.fromJson(json['change']! as Map<String, Object?>),
    [for (final finding in json['findings']! as List<Object?>) '$finding'],
  );

  final Change change;
  final List<String> findings;

  Map<String, Object?> toJson() => {
    'change': change.toJson(),
    'findings': findings,
  };
}

Future<void> review(Flow f, String branch) async {
  var change = await f.step('collect', () => collect(branch));
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

Change collect(String branch) =>
    Change(branch, branch.isEmpty ? '' : 'lib/$branch.dart');

Report inspect(Change c) => Report(c, [
  if (c.path.contains(RegExp('[A-Z]'))) '${c.path}: not lower_snake_case',
]);

Change fix(Report r) =>
    Change(r.change.id, r.change.path.replaceAll(RegExp('[A-Z]'), '_'));
