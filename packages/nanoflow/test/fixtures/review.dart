// The workflow that test/resume_test.dart resumes, and that run_review.dart
// runs in a process of its own, which the test kills.
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';
import 'package:path/path.dart' as p;

/// Three steps, the second of which waits until there is a file `go` in the
/// directory [work]. The body of each step appends a byte to the file of its
/// name in [work]: the tests count how many times it ran.
Future<String> review(Flow f, String work) async {
  final change = await f.step('collect', () {
    _ran(work, 'collect');
    return 'change';
  });
  final report = await f.step('inspect', () async {
    _ran(work, 'inspect');
    while (!File(p.join(work, 'go')).existsSync()) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return '$change: clean';
  });
  return f.step('publish', () {
    _ran(work, 'publish');
    return 'published $report';
  });
}

void _ran(String work, String step) =>
    File(p.join(work, step)).writeAsStringSync('x', mode: FileMode.append);
