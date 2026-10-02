// A graph program that test/serve_test.dart runs with `dart run`: it answers
// --graph, --input and --call for the nodes below.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

/// A step whose program exits at once but leaves a `sleep` behind in its
/// process group that holds its stdout, so that [exec] still waits. Once the
/// shell [exec] runs the program through has exited too, the `sleep` tells
/// its pid on stderr.
final leavesChild = node((Object? _) async {
  await exec('/bin/sh', [
    '-c',
    r'''
shell=$PPID
(
  while kill -0 $shell 2>/dev/null; do sleep 0.01; done
  exec /bin/sh -c 'echo "pids $$" >&2; exec sleep 1000'
) &
''',
  ]);
});

/// Starts a `sleep` with [exec] that first writes its pid to [pidFile];
/// gives what [exec] gives.
Future<String> sleepWritingPid(String pidFile) => exec('/bin/sh', [
  '-c',
  r'echo $$ > "$1.tmp" && mv "$1.tmp" "$1" && exec sleep 1000',
  'sh',
  pidFile,
]);

/// Completes once [pidFile] is there.
Future<void> pidWritten(String pidFile) async {
  while (!File(pidFile).existsSync()) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Steps that end while a program [exec] started still runs: a `sleep`,
/// whose pid goes to the file the input names. This one stops waiting for
/// it and fails.
final timesOut = node((String pidFile) async {
  final sleeping = sleepWritingPid(pidFile);
  await pidWritten(pidFile);
  await sleeping.timeout(const Duration(milliseconds: 1));
});

/// Returns without waiting for its `sleep`.
final returnsEarly = node((String pidFile) async {
  unawaited(sleepWritingPid(pidFile));
  await pidWritten(pidFile);
});

/// Waits for its `sleep`, but an error nobody awaits ends the step.
final failsUncaught = node((String pidFile) async {
  final sleeping = sleepWritingPid(pidFile);
  await pidWritten(pidFile);
  unawaited(Future<void>(() => throw StateError('nobody awaits this')));
  await sleeping;
});

final graph = Graph([
  Graph.start(collect).next(isEmpty).otherwise(inspect),
  Graph.part(inspect)
      .next(verdict)
      .then({Verdict.accepted: notify, Verdict.returned: fix}),
  Graph.part(hang),
  Graph.part(hangHard),
  Graph.part(leavesChild),
  Graph.part(timesOut),
  Graph.part(returnsEarly),
  Graph.part(failsUncaught),
]);

void main(List<String> args) => serve(
  args,
  graph,
  input: (raw) => Request.fromJson(jsonDecode(raw) as Map<String, Object?>),
);
