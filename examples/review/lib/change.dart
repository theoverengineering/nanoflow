/// What the review works on and the work of its nodes, done offline and the
/// same way every run, so that the example runs anywhere: the change of a
/// branch is the one file named after it, inspect checks the file's name with
/// a program through `exec` — as a reviewer such as `claude -p` would be run
/// — and fix renames the file.
library;

import 'dart:convert';

import 'package:nanoflow/nanoflow.dart';

/// The change under review: the file it touches; none when [path] is empty.
class Change {
  Change({required this.id, required this.path});

  factory Change.fromJson(Map<String, Object?> json) =>
      Change(id: json['id']! as String, path: json['path']! as String);

  final String id;
  final String path;

  Map<String, Object?> toJson() => {'id': id, 'path': path};
}

/// What inspect found in a change: nothing when it can go out.
class Report {
  Report({required this.change, required this.findings});

  factory Report.fromJson(Map<String, Object?> json) => Report(
    change: Change.fromJson(json['change']! as Map<String, Object?>),
    findings: [for (final finding in json['findings']! as List) '$finding'],
  );

  final Change change;
  final List<String> findings;

  Map<String, Object?> toJson() => {
    'change': change.toJson(),
    'findings': findings,
  };
}

/// The change of [branch]: the one file named after it, `lib/<branch>.dart`;
/// none for a branch without a name.
Change collect(String branch) =>
    Change(id: branch, path: branch.isEmpty ? '' : 'lib/$branch.dart');

/// Checks [change] with a program: a shell prints a finding a line when the
/// name of the file is not lower_snake_case.
Future<Report> inspect(Change change) async {
  final out = await exec('sh', ['-c', _namingCheck, 'sh', change.path]);
  return Report(change: change, findings: const LineSplitter().convert(out));
}

const _namingCheck = r'''
case "${1##*/}" in
  *[!a-z0-9_.]*) echo "$1: file names are lower_snake_case" ;;
esac''';

/// Renames the file of the change [report] is about to lower_snake_case:
/// `lib/parseConfig.dart` becomes `lib/parse_config.dart`. What it gives
/// passes inspect.
Change fix(Report report) {
  final path = report.change.path;
  final slash = path.lastIndexOf('/') + 1;
  final name = path
      .substring(slash)
      .replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}')
      .replaceAll(RegExp('[^a-z0-9_.]'), '_');
  return Change(id: report.change.id, path: path.substring(0, slash) + name);
}
