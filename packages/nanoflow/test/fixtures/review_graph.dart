// The graph from docs/dart-graph.md «Пример», with real data classes.
import 'package:nanoflow/nanoflow.dart';

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
  (Report r) async => r.findings.isEmpty ? 'accepted' : 'returned',
);
final fix = node((Report r) async => r.change);
final publish = node((Report r) async {});
final notify = node((Report r) async {});
final discard = node((Change c) async {});

final graph = Graph([
  Graph.start(collect).next(isEmpty).then(discard).otherwise(inspect),
  Graph.part(inspect).next(verdict).then({
    'accepted': {publish, notify},
    'returned': fix,
  }),
  Graph.part(fix).next(inspect),
]);
