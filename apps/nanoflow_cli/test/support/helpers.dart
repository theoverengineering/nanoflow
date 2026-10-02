import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nanoflow_cli/nanoflow_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Writes an executable POSIX shell script with [body] into a fresh temporary
/// directory, deleted after the test, and gives its path.
String script(String body) {
  final dir = Directory.systemTemp.createTempSync('nanoflow_cli_test_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File(p.join(dir.path, 'graph.sh'))
    ..writeAsStringSync('#!/bin/sh\n$body');
  final chmod = Process.runSync('chmod', ['+x', file.path]);
  if (chmod.exitCode != 0) throw StateError('chmod failed: ${chmod.stderr}');
  return file.path;
}

/// What `nanoflow` did: its exit code, stdout and stderr.
typedef Outcome = ({int code, String out, String err});

/// Runs `nanoflow` with [args]. Its stdin is [stdinStream] when given, and
/// [stdin] otherwise.
Future<Outcome> nanoflow(
  List<String> args, {
  String stdin = '',
  Stream<List<int>>? stdinStream,
}) async {
  final out = Capture();
  final err = Capture();
  final outSink = IOSink(out);
  final errSink = IOSink(err);
  final code = await runCli(
    args,
    stdin: stdinStream ?? Stream.value(utf8.encode(stdin)),
    stdout: outSink,
    stderr: errSink,
  );
  await outSink.close();
  await errSink.close();
  return (code: code, out: out.text, err: err.text);
}

/// Runs `nanoflow` with [args] as a process of its own, from its source
/// [script]: [stdin] is written to its stdin, which is then closed; without
/// [stdin] it starts with its stdin closed, as a shell's `<&-` starts it, so
/// that its fd 0 is not open. A process that has not exited after 20 seconds
/// fails the test, and is killed.
Future<Outcome> nanoflowProcess(
  List<String> args, {
  String? stdin,
  String script = 'bin/nanoflow.dart',
}) async {
  final dart = [Platform.resolvedExecutable, script, ...args];
  final process = stdin == null
      ? await Process.start('/bin/sh', ['-c', r'exec "$0" "$@" <&-', ...dart])
      : await Process.start(dart.first, dart.sublist(1));
  addTearDown(() => process.kill(ProcessSignal.sigkill));
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  // A process that exits without reading its stdin breaks the pipe.
  process.stdin.done.ignore();
  process.stdin.write(stdin ?? '');
  process.stdin.close().ignore();
  final code = await process.exitCode.timeout(const Duration(seconds: 20));
  return (code: code, out: await out, err: await err);
}

/// The error of a read of stdin when nothing has come yet and its file is
/// non-blocking, as a parent that shares it may leave it.
const unreadableStdin = FileSystemException(
  'read failed',
  '/dev/stdin',
  OSError('Resource temporarily unavailable', 35),
);

/// The bytes written to an [IOSink] built on it.
final class Capture implements StreamConsumer<List<int>> {
  final _bytes = BytesBuilder();

  /// What was written so far, as UTF-8.
  String get text => utf8.decode(_bytes.toBytes());

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach(_bytes.add);

  @override
  Future<void> close() async {}
}
