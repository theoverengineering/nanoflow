import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/compiled.dart';
import '../support/fake_program.dart';

/// The `nanoflow` executable, compiled once for this file: the memory
/// measured is the engine's own, not that of a `dart` compiling its source.
late final String nanoflowExe;

/// The resident memory of process [pid], in KB; 0 once it is gone.
Future<int> residentKb(int pid) async {
  final ps = await Process.run('ps', ['-o', 'rss=', '-p', '$pid']);
  return int.tryParse((ps.stdout as String).trim()) ?? 0;
}

void main() {
  setUpAll(() async => nanoflowExe = await compileNanoflow());

  test('a step that prints its log faster than it can be written: the log is '
      'complete, and the engine holds little of it in memory', () async {
    final fake = FakeProgram(
      {
        'start': 'flood',
        'nodes': {
          'flood': {'command': 'flood'},
        },
      },
      nodes: {'flood': 'cat flood.txt >&2'},
    );
    // About 200 MB of numbered lines, which cat prints as fast as the engine
    // reads them.
    final flood = p.join(fake.dir, 'flood.txt');
    final made = await Process.run('/bin/sh', [
      '-c',
      r'seq 1 18000000 > "$0"',
      flood,
    ]);
    expect(made.exitCode, 0, reason: '${made.stderr}');

    final engine = await Process.start(nanoflowExe, ['run', '--', fake.path]);
    addTearDown(() => engine.kill(ProcessSignal.sigkill));
    final out = engine.stdout.transform(utf8.decoder).join();
    final err = engine.stderr.transform(utf8.decoder).join();
    var exited = false;
    final code = engine.exitCode.whenComplete(() => exited = true);
    var peakKb = 0;
    while (!exited) {
      peakKb = max(peakKb, await residentKb(engine.pid));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(await code, 0, reason: await err);
    expect(await out, matches(r'^[0-9a-f-]{36}\n$'));
    expect(peakKb, lessThan(150 * 1024), reason: 'peak: ${peakKb ~/ 1024} MB');
    final log = Directory(fake.runsDir)
        .listSync(recursive: true)
        .singleWhere((entity) => p.basename(entity.path) == 'command.log');
    final compared = await Process.run('cmp', [flood, log.path]);
    expect(compared.exitCode, 0, reason: '${compared.stdout}');
  });
}
