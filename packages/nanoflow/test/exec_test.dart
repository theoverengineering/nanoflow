import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A stand-in for the process stderr that keeps what is written to it.
final class Captured implements Stdout {
  final bytes = <int>[];
  final _added = StreamController<void>.broadcast();

  String get text => utf8.decode(bytes);

  @override
  void add(List<int> data) {
    bytes.addAll(data);
    _added.add(null);
  }

  /// Waits until [text] contains [part].
  Future<void> contains(String part) async {
    while (!text.contains(part)) {
      await _added.stream.first;
    }
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Runs [body] with the process stderr replaced by [stderr].
Future<T> withStderr<T>(Captured stderr, Future<T> Function() body) =>
    IOOverrides.runZoned(body, stderr: () => stderr);

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('nanoflow_exec_'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('returns what the program printed on stdout', () async {
    expect(await exec('/bin/sh', ['-c', 'echo one; echo two']), 'one\ntwo\n');
  });

  test(
    'finds the program on PATH and passes the arguments as they are',
    () async {
      expect(
        await exec('printf', ['%s|', 'a b', r'$HOME', '"q"', '']),
        'a b|\$HOME|"q"||',
      );
    },
  );

  test('writes stdin to the program and closes it', () async {
    expect(await exec('cat', [], stdin: 'données'), 'données');
  });

  test('closes stdin at once when there is none to write', () async {
    expect(await exec('cat', []), isEmpty);
  });

  test('runs the program in workingDirectory', () async {
    expect(
      await exec('pwd', [], workingDirectory: temp.path),
      '${temp.resolveSymbolicLinksSync()}\n',
    );
  });

  test('runs the program in a process group of its own', () async {
    final ours = await Process.run('ps', ['-o', 'pgid=', '-p', '$pid']);
    final out = await exec('/bin/sh', ['-c', r'echo $$ $(ps -o pgid= -p $$)']);
    final [shell, group] = out.trim().split(RegExp(r'\s+'));
    expect(group, shell);
    expect(group, isNot((ours.stdout as String).trim()));
  });

  test('passes stderr on to the process stderr as it arrives', () async {
    final stderr = Captured();
    final go = p.join(temp.path, 'go');
    // The program ends only once the test has seen its stderr.
    final out = withStderr(
      stderr,
      () => exec('/bin/sh', [
        '-c',
        r'echo "to the log" >&2; while [ ! -e "$0" ]; do sleep 0.05; done; '
            r'echo data',
        go,
      ]),
    );
    await stderr.contains('to the log\n');
    File(go).createSync();
    expect(await out, 'data\n');
    expect(stderr.text, 'to the log\n');
  });

  test(
    'throws an ExecException when the program exits with non-zero',
    () async {
      final stderr = Captured();
      await expectLater(
        withStderr(
          stderr,
          () => exec('/bin/sh', ['-c', 'echo why >&2; exit 3']),
        ),
        throwsA(
          isA<ExecException>()
              .having((e) => e.executable, 'executable', '/bin/sh')
              .having((e) => e.exitCode, 'exitCode', 3)
              .having(
                (e) => '$e',
                'toString',
                contains('/bin/sh exited with 3'),
              ),
        ),
      );
      expect(stderr.text, 'why\n');
    },
  );
}
