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

/// What [nanoflowProcess] gives the process as its stdin: [input] is the
/// text it holds.
enum StdinKind {
  /// A pipe, written and closed.
  pipe,

  /// A regular file.
  file,

  /// A UNIX socket, written and closed, as a Node.js parent gives one.
  socket,

  /// A pipe a parent made non-blocking, written once `writeAfter` exists, a
  /// moment later: the process finds it empty when it starts reading.
  nonBlocking,

  /// `/dev/null`, whatever [input] is.
  devNull,

  /// A directory, which cannot be read.
  directory,

  /// None: fd 0 is not open, as a shell's `<&-` starts the process.
  closed,
}

/// Starts a program with its stdin a socket or a non-blocking pipe, which
/// a shell cannot make: `perl -e <it> <socket|nonBlocking> <program…>`.
/// It reads its own stdin to the end and becomes the program, with that
/// text written to the other end by a process of its own, which no one
/// waits for (it leaves at once, or after 20 s at most when `WRITE_AFTER`
/// never appears).
const _stdinMaker = r"""
use strict; use warnings; use Socket; use Fcntl; use POSIX ();
$SIG{PIPE} = 'IGNORE';
my $kind = shift @ARGV;
my $input = do { local $/; <STDIN> };
my ($r, $w);
if ($kind eq 'socket') {
  socketpair($r, $w, AF_UNIX, SOCK_STREAM, PF_UNSPEC) or die "socketpair: $!";
} else {
  pipe($r, $w) or die "pipe: $!";
  my $flags = fcntl($r, F_GETFL, 0) or die "fcntl: $!";
  fcntl($r, F_SETFL, $flags | O_NONBLOCK) or die "fcntl: $!";
}
my $pid = fork() // die "fork: $!";
if (!$pid) {
  POSIX::_exit(0) if fork();
  close $r;
  open(STDOUT, '>', '/dev/null');
  open(STDERR, '>', '/dev/null');
  if (my $after = $ENV{WRITE_AFTER}) {
    for (1 .. 2000) { last if -e $after; select(undef, undef, undef, 0.01); }
    select(undef, undef, undef, 0.3);
  }
  print {$w} $input;
  close $w;
  POSIX::_exit(0);
}
waitpid($pid, 0);
close $w;
open(STDIN, '<&', $r) or die "stdin: $!";
close $r;
exec { $ARGV[0] } @ARGV or die "exec: $!";
""";

/// Runs `nanoflow` with [args] as a process of its own, from its source
/// [script], with a [stdin] of that kind holding [input]. With
/// [StdinKind.nonBlocking], [input] is written once the file [writeAfter]
/// exists. A process that has not exited after 20 seconds fails the test,
/// and is killed.
Future<Outcome> nanoflowProcess(
  List<String> args, {
  StdinKind stdin = StdinKind.pipe,
  String input = '',
  String? writeAfter,
  String script = 'bin/nanoflow.dart',
}) async {
  final dart = [Platform.resolvedExecutable, script, ...args];
  String? from;
  if (stdin == StdinKind.file) {
    final dir = Directory.systemTemp.createTempSync('nanoflow_stdin_');
    addTearDown(() => dir.deleteSync(recursive: true));
    from = p.join(dir.path, 'input.json');
    File(from).writeAsStringSync(input);
  } else if (stdin == StdinKind.directory) {
    from = Directory.systemTemp.path;
  }
  final command = switch (stdin) {
    StdinKind.pipe => dart,
    StdinKind.file || StdinKind.directory => [
      '/bin/sh',
      '-c',
      r'exec "$0" "$@" < "$FROM"',
      ...dart,
    ],
    StdinKind.devNull => [
      '/bin/sh',
      '-c',
      r'exec "$0" "$@" </dev/null',
      ...dart,
    ],
    StdinKind.closed => ['/bin/sh', '-c', r'exec "$0" "$@" <&-', ...dart],
    StdinKind.socket ||
    StdinKind.nonBlocking => ['perl', '-e', _stdinMaker, stdin.name, ...dart],
  };
  final process = await Process.start(
    command.first,
    command.sublist(1),
    environment: {'FROM': ?from, 'WRITE_AFTER': ?writeAfter},
  );
  addTearDown(() => process.kill(ProcessSignal.sigkill));
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  // A process that exits without reading its stdin breaks the pipe.
  process.stdin.done.ignore();
  if (stdin == StdinKind.pipe || command.first == 'perl') {
    process.stdin.write(input);
  }
  process.stdin.close().ignore();
  final code = await process.exitCode.timeout(const Duration(seconds: 20));
  return (code: code, out: await out, err: await err);
}

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
