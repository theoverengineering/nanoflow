/// The review from the README as a graph of nodes, beside the workflow
/// function in `review.dart`: the same steps, each a function from an input to
/// an output that knows nothing of the others, and a graph that says what
/// follows what.
///
/// collect gives [Empty] for a branch that changes nothing, which goes to
/// discard, or [Found] with the change, which goes to inspect; inspect gives
/// [Findings], which go to fix and back to inspect, or [Clean], which goes to
/// publish and notify side by side.
library;

import 'package:nanoflow/nanoflow.dart';

import 'review.dart' as code show collect, inspect;
import 'review.dart' show Change, Report, fix;

export 'review.dart' show Change, Report;

/// What collect gives: [Empty] or [Found].
sealed class Collected {
  /// An [Empty] for `{}`, a [Found] for the JSON of a change.
  static Collected fromJson(Map<String, Object?> json) =>
      json.isEmpty ? Empty() : Found(Change.fromJson(json));

  Map<String, Object?> toJson();
}

/// The branch changes nothing.
final class Empty extends Exit<void> implements Collected {
  Empty() : super(null);

  @override
  Map<String, Object?> toJson() => {};
}

/// The change of the branch.
final class Found extends Exit<Change> implements Collected {
  Found(super.value);

  @override
  Map<String, Object?> toJson() => value.toJson();
}

/// What inspect gives: [Clean] or [Findings].
sealed class Inspected {
  /// A [Clean] for the JSON of a report without findings, [Findings] for one
  /// with.
  static Inspected fromJson(Map<String, Object?> json) {
    final report = Report.fromJson(json);
    return report.findings.isEmpty ? Clean(report) : Findings(report);
  }

  Map<String, Object?> toJson();
}

/// Inspect found nothing: the change can go out.
final class Clean extends Exit<Report> implements Inspected {
  Clean(super.value);

  @override
  Map<String, Object?> toJson() => value.toJson();
}

/// Inspect found something to fix.
final class Findings extends Exit<Report> implements Inspected {
  Findings(super.value);

  @override
  Map<String, Object?> toJson() => value.toJson();
}

/// The change of [branch], or [Empty] when it changes nothing.
Collected collect(String branch) {
  final change = code.collect(branch);
  return change.path.isEmpty ? Empty() : Found(change);
}

/// Checks [change] with a program, as `review.dart`'s inspect does.
Future<Inspected> inspect(Change change) async {
  final report = await code.inspect(change);
  return report.findings.isEmpty ? Clean(report) : Findings(report);
}

void discard(void _) => print('nothing to review');

void publish(Report report) => print('published ${report.change.path}');

void notify(Report report) => print('${report.change.id}: accepted');

/// Reviews the change of a branch.
final reviewGraph = Graph<String, void>('reviewGraph', [
  Graph.start(collect).next({Empty: discard, Found: inspect}),
  Graph.part(inspect).next({
    Clean: {publish, notify},
    Findings: fix,
  }),
  Graph.part(fix).next(inspect),
]);
