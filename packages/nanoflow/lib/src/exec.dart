import 'dart:convert';
import 'dart:io';

/// A program that [exec] ran exited with a code other than 0.
final class ExecException implements Exception {
  ExecException(this.executable, this.exitCode);

  /// The program, as [exec] was given it.
  final String executable;

  final int exitCode;

  @override
  String toString() => 'ExecException: $executable exited with $exitCode';
}

/// Runs [executable] with [arguments] and gives what it printed on stdout.
///
/// The program runs in a process group of its own, so that a stop of the
/// step ends it together with every process it started. [stdin], if given,
/// is written to the program's stdin; either way stdin is closed then. The
/// program's stderr goes to the stderr of this process as it arrives: for a
/// step, that is the step's log.
///
/// [executable] is looked up on `PATH` unless it holds a `/`; a relative
/// path is taken from [workingDirectory], the current directory by default.
///
/// Throws an [ExecException] when the program exits with a code other than
/// 0, and a [StateError] once the step is stopping.
Future<String> exec(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  String? stdin,
}) async {
  if (_stopping) {
    throw StateError('the step is stopping; $executable is not started');
  }
  final process = await Process.start('/bin/sh', [
    '-c',
    _inGroup,
    'sh',
    executable,
    ...arguments,
  ], workingDirectory: workingDirectory);
  _running.add(process);
  // A stop that came while the shell was starting may have finished
  // already; the shell ends the program on its own.
  if (_stopping) process.kill();
  try {
    if (stdin != null) process.stdin.add(utf8.encode(stdin));
    // A program that exits without reading its stdin breaks the pipe.
    process.stdin.close().ignore();
    final out = utf8.decodeStream(process.stdout);
    final log = stderr;
    final logged = process.stderr.listen(log.add).asFuture<void>();
    final exitCode = await process.exitCode;
    await logged;
    if (exitCode != 0) {
      out.ignore();
      throw ExecException(executable, exitCode);
    }
    return await out;
  } finally {
    _running.remove(process);
  }
}

/// Stops every program [exec] is running, with every process each one
/// started, and refuses to start new ones.
///
/// Each program's process group gets SIGTERM, and SIGKILL if any of it is
/// still running 5 s later. Completes once every program has ended.
Future<void> stopRunning() async {
  _stopping = true;
  // Programs whose start was under way when the stop came are stopped on a
  // later round.
  while (_running.isNotEmpty) {
    final stopped = List.of(_running);
    for (final process in stopped) {
      process.kill();
    }
    await Future.wait([for (final process in stopped) process.exitCode]);
    _running.removeAll(stopped);
  }
}

/// The `/bin/sh -c` script that runs a program — `"$@"` — in a process group
/// of its own and ends the group when the shell gets SIGTERM, SIGINT or
/// SIGHUP: SIGTERM to the group, then SIGKILL after 5 s if any of it is still
/// running.
///
/// The shell exits with the program's code. With job control (`set -m`) the
/// program, started in the background, leads a new process group, and its
/// stdin is not redirected from /dev/null. The shell's own stderr — job
/// notices such as `Done` — goes to /dev/null; the program gets the real one
/// through fd 3. The `while` loop waits again if `wait` returned while the
/// program is only stopped.
const _inGroup = r'''
stop() {
  trap '' TERM INT HUP
  set +m
  kill -TERM -$!
  i=0
  while kill -0 -$! && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  kill -KILL -$!
  exit 143
}
exec 3>&2 2>/dev/null
set -m
trap stop TERM INT HUP
"$@" 2>&3 3>&- &
while :; do
  wait $!
  code=$?
  kill -0 $! || exit $code
done
''';

/// The shells [exec] has started that have not ended yet.
final _running = <Process>{};

/// Whether [stopRunning] was called.
var _stopping = false;
