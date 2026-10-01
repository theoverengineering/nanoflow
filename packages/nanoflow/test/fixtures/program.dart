// A graph program that test/serve_test.dart runs with `dart run`: it answers
// --graph, --input and --call for the nodes below.
import 'dart:convert';

import 'package:nanoflow/nanoflow.dart';

enum Verdict { accepted, returned }

class Request {
  Request({required this.branch});

  factory Request.fromJson(Map<String, Object?> json) =>
      Request(branch: json['branch'] as String);

  final String branch;

  Map<String, Object?> toJson() => {'branch': branch};
}

class Change {
  Change({required this.id, required this.path});

  Change.fromJson(Map<String, Object?> json)
    : id = json['id'] as String,
      path = json['path'] as String;

  final String id;
  final String path;

  Map<String, Object?> toJson() => {'id': id, 'path': path};
}

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

final collect = node(
  (Request r) async => Change(id: '1', path: 'lib/${r.branch}.dart'),
);
final isEmpty = fork((Change c) async => c.path.isEmpty);
final inspect = node((Change c) async => Report(change: c, findings: []));
final verdict = fork(
  (Report r) async => r.findings.isEmpty ? Verdict.accepted : Verdict.returned,
);
final notify = node((Report r) async {
  print('notified about change ${r.change.id}');
});
final fix = node((Report r) async {
  if (r.findings.isNotEmpty) throw StateError('cannot fix ${r.change.path}');
  return r.change;
});

/// A step that only a stop ends: a shell that starts a `sleep`, tells both
/// pids on stderr and waits.
final hang = node((Object? _) async {
  await exec('/bin/sh', ['-c', r'sleep 1000 & echo "pids $$ $!" >&2; wait']);
});

/// Like [hang], but the shell and the `sleep` ignore SIGTERM.
final hangHard = node((Object? _) async {
  await exec('/bin/sh', [
    '-c',
    r'trap "" TERM; sleep 1000 & echo "pids $$ $!" >&2; wait',
  ]);
});

final graph = Graph([
  Graph.start(collect).next(isEmpty).otherwise(inspect),
  Graph.part(inspect)
      .next(verdict)
      .then({Verdict.accepted: notify, Verdict.returned: fix}),
  Graph.part(hang),
  Graph.part(hangHard),
]);

void main(List<String> args) => serve(
  args,
  graph,
  input: (raw) => Request.fromJson(jsonDecode(raw) as Map<String, Object?>),
);
