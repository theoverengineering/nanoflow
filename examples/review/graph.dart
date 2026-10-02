// The review graph from README «Формат», written in Dart as
// docs/dart-graph.md describes. From this directory:
//
//   nanoflow run -- dart run graph.dart < input.json
import 'dart:convert';

import 'package:nanoflow/nanoflow.dart';

/// What to review: a branch.
class Request {
  Request({required this.branch});

  factory Request.fromJson(Map<String, Object?> json) =>
      Request(branch: json['branch'] as String);

  final String branch;

  Map<String, Object?> toJson() => {'branch': branch};
}

/// The change under review: the file it touches, none when the path is
/// empty.
class Change {
  Change({required this.id, required this.path});

  factory Change.fromJson(Map<String, Object?> json) =>
      Change(id: json['id'] as String, path: json['path'] as String);

  final String id;
  final String path;

  Map<String, Object?> toJson() => {'id': id, 'path': path};
}

/// What inspect found in a change: nothing when it can go out.
class Report {
  Report({required this.change, required this.findings});

  factory Report.fromJson(Map<String, Object?> json) => Report(
    change: Change.fromJson(json['change'] as Map<String, Object?>),
    findings: (json['findings'] as List<Object?>).cast<String>(),
  );

  final Change change;
  final List<String> findings;

  Map<String, Object?> toJson() => {
    'change': change.toJson(),
    'findings': findings,
  };
}

enum Verdict { accepted, returned }

/// Takes the change of the branch: here, the one file named after it; a
/// branch without a name changes nothing.
final collect = node(
  (Request r) async => Change(
    id: r.branch,
    path: r.branch.isEmpty ? '' : 'lib/${r.branch}.dart',
  ),
);

final isEmpty = fork((Change c) async => c.path.isEmpty);

/// Checks the change with a program, as a reviewer such as `claude -p`
/// would: a shell prints a finding a line when the file name is not
/// lower_snake_case.
final inspect = node((Change c) async {
  final out = await exec('sh', ['-c', _namingCheck, 'sh', c.path]);
  return Report(change: c, findings: const LineSplitter().convert(out));
});

const _namingCheck = r'''
case "${1##*/}" in
  *[!a-z0-9_.]*) echo "$1: file names are lower_snake_case" ;;
esac''';

final verdict = fork(
  (Report r) async => r.findings.isEmpty ? Verdict.accepted : Verdict.returned,
);

/// Renames the file to lower_snake_case: `lib/parseConfig.dart` becomes
/// `lib/parse_config.dart`. What it makes always passes inspect.
final fix = node((Report r) async {
  final path = r.change.path;
  final slash = path.lastIndexOf('/') + 1;
  final name = path
      .substring(slash)
      .replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}')
      .replaceAll(RegExp('[^a-z0-9_.]'), '_');
  return Change(id: r.change.id, path: path.substring(0, slash) + name);
});

final publish = node((Report r) async {
  print('published ${r.change.path}');
});

final notify = node((Report r) async {
  print('${r.change.id}: accepted');
});

final discard = node((Change c) async {
  print('nothing to review');
});

final graph = Graph([
  Graph.start(collect).next(isEmpty).then(discard).otherwise(inspect),
  Graph.part(inspect).next(verdict).then({
    Verdict.accepted: {publish, notify},
    Verdict.returned: fix,
  }),
  Graph.part(fix).next(inspect),
]);

void main(List<String> args) => serve(
  args,
  graph,
  input: (raw) => Request.fromJson(jsonDecode(raw) as Map<String, Object?>),
);
