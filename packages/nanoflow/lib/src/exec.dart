import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
/// [executable] is a program, never a shell builtin: it is looked up on
/// `PATH` unless it holds a `/`; a relative path is taken from
/// [workingDirectory], the current directory by default.
///
/// The program runs through `/bin/bash` when there is one, else through
/// `/bin/sh`: a shell that keeps job control on without a terminal, as bash
/// does, gives it its group. One that does not, as dash, is found out before
/// the first program starts.
///
/// Throws an [ExecException] when the program exits with a code other than
/// 0, a [FormatException] when its stdout is not UTF-8, and a [StateError]
/// once the step is stopping, or when the shell cannot run the program in a
/// group of its own.
Future<String> exec(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  String? stdin,
}) => execIn(
  _shell,
  executable,
  arguments,
  workingDirectory: workingDirectory,
  stdin: stdin,
);

/// [exec] through [shell].
Future<String> execIn(
  String shell,
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  String? stdin,
}) async {
  _refuseWhileStopping(executable);
  if (!await (_groups[shell] ??= _givesGroups(shell))) {
    throw StateError(
      'exec cannot run $executable in a process group of its own, so a '
      'stop of the step could not end it: $shell turns job control off '
      'without a terminal; install bash',
    );
  }
  _refuseWhileStopping(executable);
  final process = await Process.start(shell, [
    '-c',
    inGroupScript,
    'sh',
    executable,
    ...arguments,
  ], workingDirectory: workingDirectory);
  final group = Completer<int?>();
  final program = (shell: process, group: group.future);
  _running.add(program);
  // A stop that came while the shell was starting may have finished
  // already; the shell ends the program on its own.
  if (_stopping) process.kill();
  try {
    if (stdin != null) process.stdin.add(utf8.encode(stdin));
    // A program that exits without reading its stdin breaks the pipe.
    process.stdin.close().ignore();
    // Bytes, decoded only once the exit code is known: stdout that is not
    // UTF-8 must not fail before the caller awaits.
    final out = process.stdout.fold(
      BytesBuilder(copy: false),
      (bytes, chunk) => bytes..add(chunk),
    );
    final logged = _log(process.stderr, stderr, group);
    final exitCode = await process.exitCode;
    final printed = await out;
    await logged;
    if (exitCode != 0) throw ExecException(executable, exitCode);
    return utf8.decode(printed.takeBytes());
  } finally {
    _running.remove(program);
  }
}

/// Passes [shellStderr], the stderr of the shell that runs a program, on to
/// [log] as it arrives, all but the line that tells the program's process
/// group: [group] completes with the group's id from it, or with `null`
/// when [shellStderr] ends without it.
///
/// The line comes before anything the program writes, so lines are only
/// looked at until it comes; any before it are the shell's own.
Future<void> _log(
  Stream<List<int>> shellStderr,
  IOSink log,
  Completer<int?> group,
) async {
  var head = <int>[];
  try {
    await for (final chunk in shellStderr) {
      if (group.isCompleted) {
        log.add(chunk);
        continue;
      }
      head += chunk;
      for (var end = head.indexOf(0x0A); end >= 0; end = head.indexOf(0x0A)) {
        final line = head.sublist(0, end + 1);
        head = head.sublist(end + 1);
        final told = _groupLine.firstMatch(latin1.decode(line));
        if (told == null) {
          log.add(line);
          continue;
        }
        group.complete(int.parse(told[1]!));
        if (head.isNotEmpty) log.add(head);
        head = [];
        break;
      }
    }
  } finally {
    if (head.isNotEmpty) log.add(head);
    if (!group.isCompleted) group.complete(null);
  }
}

void _refuseWhileStopping(String executable) {
  if (_stopping) {
    throw StateError('the step is stopping; $executable is not started');
  }
}

/// Whether [shell] runs the program of [inGroupScript] in a process group of
/// its own: a program it runs that way tells whether it leads its group.
Future<bool> _givesGroups(String shell) async {
  final probe = await Process.run(shell, [
    '-c',
    inGroupScript,
    'sh',
    '/bin/sh',
    '-c',
    r'kill -0 -$$ 2>/dev/null',
  ]);
  return probe.exitCode == 0;
}

/// Stops every program [exec] is running, with every process each one
/// started, and refuses to start new ones.
///
/// Each program's process group gets SIGTERM, and SIGKILL if any of it is
/// still running 5 s later — also the group of a program that has exited
/// already, but left a process behind that keeps [exec] waiting, as one
/// that holds the program's stdout does. Completes once every program has
/// ended.
Future<void> stopRunning() async {
  _stopping = true;
  // Programs whose start was under way when the stop came are stopped on a
  // later round.
  while (_running.isNotEmpty) {
    final stopped = List.of(_running);
    await Future.wait([for (final program in stopped) _stop(program)]);
    _running.removeAll(stopped);
  }
}

/// Stops [program]. While its shell runs, the shell ends the program's
/// group; once the shell has exited, what is left of the group is ended
/// here.
Future<void> _stop(_Program program) async {
  program.shell.kill();
  await program.shell.exitCode;
  if (await program.group case final group?) {
    await Process.run('/bin/sh', ['-c', _endGroupScript, 'sh', '$group']);
  }
}

/// Shell code that defines `end_group`, which ends the process group `$1`:
/// SIGTERM, then SIGKILL after 5 s if any of it is still running.
const _endGroup = r'''
end_group() {
  kill -TERM -$1 || return 0
  i=0
  while kill -0 -$1 && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  kill -KILL -$1
}
''';

/// The `sh -c` script that ends the process group its argument names.
const _endGroupScript = '${_endGroup}end_group "\$1"\n';

/// The `sh -c` script that runs a program — `"$@"` — in a process group of
/// its own and ends the group when the shell gets SIGTERM, SIGINT or
/// SIGHUP: SIGTERM to the group, then SIGKILL after 5 s if any of it is still
/// running.
///
/// The shell exits with the program's code. With job control (`set -m`) the
/// program, started in the background, leads a new process group. That needs
/// a shell that keeps job control on without a terminal, as bash does; dash
/// turns it off. The program gets the shell's stdin through fd 4: without
/// job control, a background job's stdin would be /dev/null. The job is a
/// `/bin/sh` that first tells the group's id — its own pid — on stderr in a
/// line [_groupLine] matches, so that a stop can end the group after this
/// shell has exited; then its `exec` makes the job the program itself,
/// found on `PATH`, rather than a builtin. The shell's own stderr — job
/// notices such as `Done` — goes to /dev/null; the job gets the real one
/// through fd 3. The `while` loop waits again if `wait` returned while the
/// program is only stopped.
const inGroupScript =
    _endGroup +
    r'''
stop() {
  trap '' TERM INT HUP
  set +m
  end_group $!
  exit 143
}
exec 3>&2 2>/dev/null 4<&0
set -m
trap stop TERM INT HUP
/bin/sh -c 'echo "nanoflow-exec-group $$" >&2; exec "$@"' sh "$@" \
  <&4 4<&- 2>&3 3>&- &
while :; do
  wait $!
  code=$?
  kill -0 $! || exit $code
done
''';

/// The line the job of [inGroupScript] tells its process group with.
final _groupLine = RegExp(r'^nanoflow-exec-group (\d+)\n$');

/// The shell [exec] runs programs through.
final String _shell = File('/bin/bash').existsSync() ? '/bin/bash' : '/bin/sh';

/// Whether each shell asked runs programs in process groups of their own.
final _groups = <String, Future<bool>>{};

/// A program [exec] runs: the shell it runs through, and the id of the
/// program's process group once the shell has told it — `null` when the
/// shell ended without telling it.
typedef _Program = ({Process shell, Future<int?> group});

/// The programs [exec] has started that it has not returned for yet.
final _running = <_Program>{};

/// Whether [stopRunning] was called.
var _stopping = false;
