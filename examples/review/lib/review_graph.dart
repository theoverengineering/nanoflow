/// The review from the README as a graph of nodes, beside the workflow
/// function in `review.dart`: the same steps, each a node that runs as one
/// effect and knows nothing of the others, and a graph whose routes say what
/// follows what.
///
/// collect gives [Empty] for a branch that changes nothing, which goes to
/// discard, or [Found] with the change, which goes to inspect; a report of
/// inspect with findings goes to fix and back to inspect, one without goes to
/// publish and notify side by side, and when both are done to report.
library;

import 'package:nanoflow/nanoflow.dart';

import 'review.dart' as code show collect, fix, inspect;
import 'review.dart' show Change, Report;

export 'review.dart' show Change, Report;

/// What collect gives: [Empty] or [Found].
sealed class Collected {
  /// An [Empty] for the JSON of a branch, a [Found] for the JSON of a change.
  static Collected fromJson(Map<String, Object?> json) =>
      json.containsKey('branch')
      ? Empty(json['branch']! as String)
      : Found(Change.fromJson(json));

  Map<String, Object?> toJson();
}

/// The branch changes nothing.
final class Empty implements Collected {
  Empty(this.branch);

  final String branch;

  @override
  Map<String, Object?> toJson() => {'branch': branch};
}

/// The change of the branch.
final class Found implements Collected {
  Found(this.change);

  final Change change;

  @override
  Map<String, Object?> toJson() => change.toJson();
}

/// The change of the branch, or Empty when it changes nothing.
final collect = node('collect', (String branch) async {
  final change = code.collect(branch);
  return change.path.isEmpty ? Empty(branch) : Found(change);
});

/// Checks the name of the change's file with a program, as a reviewer
/// such as `claude -p` would be run.
final inspect = node('inspect', (Change change) async => code.inspect(change));

/// Renames the file to lower_snake_case, for inspect to check again.
final fix = node('fix', (Report report) async => code.fix(report));

/// Ends the review of a branch that changes nothing.
final discard = node(
  'discard',
  (String branch) async => print('nothing to review'),
);

/// Puts the change out.
final publish = node('publish', (Report report) async {
  final done = 'published ${report.change.path}';
  print(done);
  return done;
});

/// Tells the branch's author it is accepted.
final notify = node('notify', (Report report) async {
  final said = '${report.change.id}: accepted';
  print(said);
  return said;
});

/// Sums up the review once the change is out and the author is told.
final report = node('report', ((String, String) sent) async {
  print('${sent.$1}; ${sent.$2}');
});

/// Reviews the change of a branch.
final reviewGraph = Graph<String, void>('reviewGraph', [
  Graph.start(collect).next(
    (collected) => switch (collected) {
      Empty(:final branch) => discard(branch),
      Found(:final change) => inspect(change),
    },
  ),
  Graph.part(inspect)
      .next((r) => r.findings.isEmpty ? {publish(r), notify(r)} : fix(r)),
  Graph.part(fix).next((change) => inspect(change)),
  Graph.join([publish, notify]).next(((String, String) sent) => report(sent)),
]);
