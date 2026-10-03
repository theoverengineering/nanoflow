import 'dart:async';
import 'dart:io';

import 'package:nanoflow_process/nanoflow_process.dart';
import 'package:test/test.dart';

void main() {
  test('is not supported', () {
    expect(UnsupportedProcesses().supported, isFalse);
  });

  test('knows no start, not even of this process', () {
    expect(UnsupportedProcesses().startOf(pid), isNull);
  });

  test('never tells an exit, not even of a process that is gone', () async {
    final processes = UnsupportedProcesses();
    addTearDown(processes.close);
    // The Dart executable: the one program at hand on every OS.
    final gone = await Process.start(Platform.resolvedExecutable, [
      '--version',
    ]);
    await gone.exitCode;

    await expectLater(
      processes.exitOf(gone.pid).timeout(const Duration(milliseconds: 200)),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('closes', () async {
    await UnsupportedProcesses().close();
  });
}
