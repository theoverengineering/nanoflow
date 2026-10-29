// Graphs of nodes: review, a workflow, whose routes switch over a sealed
// output, pick with ?:, and run a set into a join, one of them a top-level
// function; polish, a node of review that shares a node with it, whose ?:
// route decides nothing and whose other route has if and switch statements,
// a throw and a statement that decides nothing; announce, whose join has no
// route.
import 'package:nanoflow/nanoflow.dart';

final class Change {
  Change(this.path);

  final String path;
}

enum Verdict { pass, retry, fail }

final class Report {
  Report(this.path, this.findings, this.verdict);

  final String path;
  final int findings;
  final Verdict verdict;
}

sealed class Collected {}

final class Empty implements Collected {
  Empty(this.branch);

  final String branch;
}

final class Found implements Collected {
  Found(this.change);

  final Change change;
}

/// The change of the branch, or Empty when it changes nothing.
final collect = node<String, Collected>(
  'collect',
  (branch) async => branch.isEmpty ? Empty(branch) : Found(Change(branch)),
);

/// What is wrong with the change.
final inspect = node(
  'inspect',
  (Change change) async => Report(change.path, 0, Verdict.pass),
);

final fix = node('fix', (Report report) async => Change('${report.path}!'));

final discard = node('discard', (String branch) async => branch);

final publish = node('publish', (Report report) async => report.path);

final notify = node('notify', (Report report) async => report.findings);

final summarize = node(
  'summarize',
  ((String, int) sent) async => '${sent.$1}: ${sent.$2}',
);

final giveUp = node('giveUp', (Report report) async => report);

/// Reviews the change of a branch.
final review = Graph<String, String>('review', [
  Graph.start(collect).next(
    (collected) => switch (collected) {
      Empty(:final branch) => discard(branch),
      Found(:final change) when change.path.endsWith('.md') => discard(
        change.path,
      ),
      Found(:final change) => inspect(change),
    },
  ),
  Graph.part(inspect).next(
    (report) => report.findings == 0
        ? {publish(report), notify(report)}
        : polish(report),
  ),
  Graph.part(polish).next(published),
  Graph.join([publish, notify]).next(((String, int) sent) => summarize(sent)),
]);

/// Fixes a change until its report has no findings, or gives up.
final polish = Graph<Report, Report>('polish', [
  Graph.start(fix).next(
    (change) => change.path.endsWith('!')
        ? inspect(change)
        : inspect(Change('${change.path}!')),
  ),
  // A pass falls off the end of the route, which gives null.
  // ignore: body_might_complete_normally_nullable
  Graph.part(inspect).next((report) {
    if (report.findings > 9) print('${report.path}: many findings');
    if (report.findings == 0) return null;
    switch (report.verdict) {
      case Verdict.retry:
        return fix(report);
      case Verdict.fail when report.findings > 3:
        throw StateError('${report.path} cannot be fixed');
      case Verdict.fail:
        return giveUp(report);
      case Verdict.pass:
    }
  }),
]);

// Publishes a report and notifies of it side by side; the record of the two
// is the result.
final announce = Graph<Report, (String, int)>('announce', [
  Graph.start(publish),
  Graph.start(notify),
  Graph.join([publish, notify]),
]);

/// Where a polished report goes: to publish and notify, side by side.
Object? published(Report report) => {publish(report), notify(report)};
