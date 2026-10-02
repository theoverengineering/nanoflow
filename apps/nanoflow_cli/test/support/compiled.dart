import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Compiles `bin/nanoflow.dart` to an executable in a temporary directory,
/// which is deleted once the tests of the file are over; gives its path. For
/// `setUpAll`: a test that needs the engine as a process of its own, not a
/// `dart` wrapper running its source.
Future<String> compileNanoflow() async {
  final dir = Directory.systemTemp.createTempSync('nanoflow_exe_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final exe = p.join(dir.path, 'nanoflow');
  // Far longer than a compile takes, and far shorter than the 12 minutes
  // the test package gives a setUpAll.
  final compiled = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'exe',
    'bin/nanoflow.dart',
    '-o',
    exe,
  ]).timeout(const Duration(minutes: 3));
  if (compiled.exitCode != 0) {
    throw StateError('cannot compile nanoflow: ${compiled.stderr}');
  }
  return exe;
}
