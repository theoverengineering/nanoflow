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
/// The program runs in [workingDirectory], the current directory by
/// default, with [environment] added to the environment of this process,
/// and with an empty stdin. Its stderr goes, as it arrives, to the log of
/// the step `exec` is called in — from the body of `f.step` or from code the
/// body calls — and anywhere else to the stderr of this process. A program
/// that writes to a step's log faster than the log is written waits on its
/// pipe.
///
/// The program runs in a process group of its own, so that it is stopped
/// together with every process it started: SIGTERM to the group, then
/// SIGKILL if any of it still runs 5 s later. That happens
///
/// - when the session of a `Flow` that `exec` is called in — from its
///   workflow or from one of its steps — is stopped: by `flow.stop()`, or
///   by a failure of the session's store. `exec` then throws the
///   `FlowStoppedException` or the `StorageException`, and throws it at once
///   when called in that session again;
/// - when this process ends, however it ends, even killed with SIGKILL: the
///   shell that runs the program watches a pipe from this process, which
///   the system closes then.
///
/// A program started in another isolate, as `Isolate.run` runs code,
/// belongs to no session: only the end of the process stops it. Start
/// programs from the code of the workflow itself.
///
/// [executable] is a program, never a shell builtin: it is looked up on
/// `PATH` unless it holds a `/`; a relative path is taken from
/// [workingDirectory].
///
/// The program runs through `/bin/bash` when there is one, else through
/// `/bin/sh`: a shell that keeps job control on without a terminal, as bash
/// does, gives it its group. One that does not, as dash, is found out before
/// the first program starts.
///
/// A writer whose reader has exited is killed by SIGPIPE, as from a shell,
/// but only when it writes next: the program runs through `/usr/bin/perl`,
/// which gives SIGPIPE back the default that the Dart VM takes away. In
/// `tail -f server.log | grep -m1 listening` grep exits at the first matching
/// line, and `tail -f` ends once another line is appended to the log; if the
/// log stays quiet the pipeline never ends, as in a shell. To wait for a ready
/// line use `until grep -q listening server.log; do sleep 0.2; done`. Without
/// perl the program starts with SIGPIPE ignored, and a writer that does not
/// stop on a write error — `tail -f` on macOS, a shell loop — runs on forever.
///
/// The program cannot ask anything on the terminal the app runs in: its
/// group is not the terminal's foreground group, so a program that asks
/// there — git for credentials, ssh about a host key, sudo for a password —
/// is stopped by the system, and `exec` waits until the program is stopped
/// as above. Run such programs so that they do not ask, and they fail at
/// once with the reason in the log: `environment: {'GIT_TERMINAL_PROMPT':
/// '0'}` for git, `ssh -o BatchMode=yes`, `sudo -n`.
///
/// Throws an [ExecException] when the program exits with a code other than
/// 0, a [FormatException] when its stdout is not UTF-8, and a [StateError]
/// when the shell cannot run the program in a group of its own.
Future<String> exec(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) => execIn(
  _shell,
  executable,
  arguments,
  workingDirectory: workingDirectory,
  environment: environment,
);

/// [exec] through [shell].
Future<String> execIn(
  String shell,
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) {
  final scope = Zone.current[_scopeKey] as ExecScope?;
  final log = Zone.current[_logKey] as ProgramLog?;
  // The stderr of this process as the caller has it.
  final processStderr = stderr;
  Future<String> run() => _exec(
    shell,
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    scope: scope,
    log: log,
    stderr: processStderr,
  );
  return scope == null ? run() : scope.zone.run(run);
}

/// The programs [exec] runs in a zone with [zoneValues] — a session's — and
/// in the zones forked from it: they are stopped together.
final class ExecScope {
  ExecScope(this.zone);

  /// The zone [exec] does its own work in for a program of the scope, so
  /// that it registers nothing in the zone it is called in.
  final Zone zone;

  /// The zone values that give [exec] this scope.
  late final Map<Object?, Object?> zoneValues = {_scopeKey: this};

  /// The programs of the scope that run.
  final _programs = <_Program>{};

  /// What [stop] was given; `null` until it is called.
  Object? _reason;

  /// Stops every program of the scope, and starts none any more: [exec]
  /// throws [reason] in the scope from now on, also for a program that it
  /// stopped. Only the first call counts.
  void stop(Object reason) {
    if (_reason != null) return;
    _reason = reason;
    for (final program in _programs) {
      zone.run(() => _stop(program)).ignore();
    }
  }

  void _refuseWhenStopped() {
    if (_reason case final reason?) throw reason;
  }
}

/// Where [exec] writes the stderr of the programs it runs in a zone with
/// [logZoneValues] of it — the zone of a step's body.
abstract interface class ProgramLog {
  /// Adds [bytes] to the log; gives `false` when the log takes nothing any
  /// more, and [exec] writes them to the stderr of this process instead.
  bool add(List<int> bytes);

  /// How many of the bytes added are not written yet.
  int get unwritten;

  /// Completes once what was added is written.
  Future<void> flush();
}

/// The zone values that make [exec] write the stderr of its programs to
/// [log].
Map<Object?, Object?> logZoneValues(ProgramLog log) => {_logKey: log};

final _scopeKey = Object();
final _logKey = Object();

/// How much of a step's log may wait to be written before [exec] stops
/// reading the program's stderr until it is: a program that writes faster
/// than the log is written then waits on its pipe, rather than this process
/// holding the log in memory.
const maxUnwrittenLog = 1 << 20;

/// [execIn] in the zone of [scope], if any; the program's stderr goes to
/// [log], or to [stderr] when there is none or it takes nothing.
Future<String> _exec(
  String shell,
  String executable,
  List<String> arguments, {
  required String? workingDirectory,
  required Map<String, String>? environment,
  required ExecScope? scope,
  required ProgramLog? log,
  required IOSink stderr,
}) async {
  scope?._refuseWhenStopped();
  if (!await (_groups[shell] ??= _givesGroups(shell))) {
    throw StateError(
      'exec cannot run $executable in a process group of its own, so it '
      'could not be stopped with what it starts: $shell turns job control '
      'off without a terminal; install bash',
    );
  }
  scope?._refuseWhenStopped();
  final process = await _startInGroup(
    shell,
    [executable, ...arguments],
    workingDirectory: workingDirectory,
    environment: environment,
  );
  final group = Completer<int?>();
  final program = _Program(process, group.future);
  try {
    // Bytes, decoded only once the exit code is known: stdout that is not
    // UTF-8 must not fail before the caller awaits.
    final out = process.stdout.fold(
      BytesBuilder(copy: false),
      (bytes, chunk) => bytes..add(chunk),
    );
    final logged = _log(process.stderr, log, stderr, group);
    if (scope != null) {
      scope._programs.add(program);
      // A stop that came while the shell was starting.
      if (scope._reason != null) unawaited(_stop(program));
    }
    final exitCode = await process.exitCode;
    final printed = await out;
    await logged;
    if (program.stopped) scope!._refuseWhenStopped();
    if (exitCode != 0) throw ExecException(executable, exitCode);
    return utf8.decode(printed.takeBytes());
  } finally {
    scope?._programs.remove(program);
    // The shell has exited: the pipe it watched has done its work.
    process.stdin.close().ignore();
  }
}

/// Starts [shell] running [program] with [inGroupScript]. The shell's stdin
/// is the pipe it watches: it must stay open until the shell has exited.
Future<Process> _startInGroup(
  String shell,
  List<String> program, {
  String? workingDirectory,
  Map<String, String>? environment,
}) => Process.start(
  shell,
  ['-c', inGroupScript, 'sh', ...program],
  workingDirectory: workingDirectory,
  environment: environment,
);

/// Passes [shellStderr], the stderr of the shell that runs a program, on to
/// [log] as it arrives — or to [stderr] when there is no log, or it takes
/// nothing — all but the line that tells the program's process group:
/// [group] completes with the group's id from it, or with `null` when
/// [shellStderr] ends without it. While more than [maxUnwrittenLog] bytes of
/// the log wait to be written, [shellStderr] is not read.
///
/// The line comes before anything the program writes, so lines are only
/// looked at until it comes; any before it are the shell's own.
Future<void> _log(
  Stream<List<int>> shellStderr,
  ProgramLog? log,
  IOSink stderr,
  Completer<int?> group,
) async {
  Future<void> pass(List<int> bytes) async {
    if (log == null || !log.add(bytes)) {
      stderr.add(bytes);
    } else if (log.unwritten > maxUnwrittenLog) {
      await log.flush();
    }
  }

  var head = <int>[];
  try {
    await for (final chunk in shellStderr) {
      if (group.isCompleted) {
        await pass(chunk);
        continue;
      }
      head += chunk;
      for (var end = head.indexOf(0x0A); end >= 0; end = head.indexOf(0x0A)) {
        final line = head.sublist(0, end + 1);
        head = head.sublist(end + 1);
        final told = _groupLine.firstMatch(latin1.decode(line));
        if (told == null) {
          await pass(line);
          continue;
        }
        group.complete(int.parse(told[1]!));
        if (head.isNotEmpty) await pass(head);
        head = [];
        break;
      }
    }
  } finally {
    if (!group.isCompleted) group.complete(null);
    if (head.isNotEmpty) await pass(head);
  }
}

/// Whether [shell] runs the program of [inGroupScript] in a process group of
/// its own: a program it runs that way tells whether it leads its group.
Future<bool> _givesGroups(String shell) async {
  final probe = await _startInGroup(shell, [
    '/bin/sh',
    '-c',
    r'kill -0 -$$ 2>/dev/null',
  ]);
  probe.stdout.drain<void>().ignore();
  probe.stderr.drain<void>().ignore();
  final exitCode = await probe.exitCode;
  probe.stdin.close().ignore();
  return exitCode == 0;
}

/// Stops [program]. While its shell runs, the shell ends the program's
/// group; once the shell has exited, what is left of the group is ended
/// here — also the group of a program that has exited already, but left a
/// process behind that keeps [exec] waiting, as one that holds the
/// program's stdout does. Completes once the program has ended.
Future<void> _stop(_Program program) async {
  program.stopped = true;
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
/// its own, and ends the group when the shell gets SIGTERM, SIGINT or SIGHUP
/// or its stdin closes: SIGTERM to the group, then SIGKILL after 5 s if any
/// of it is still running.
///
/// The shell exits with the program's code, or with 143 when it ended the
/// group. With job control (`set -m`) the program, started in the
/// background, leads a new process group. That needs a shell that keeps job
/// control on without a terminal, as bash does; dash turns it off. The job
/// is a `/bin/sh` that first tells the group's id — its own pid — on stderr
/// in a line [_groupLine] matches, so that a stop can end the group after
/// this shell has exited; then its `exec` makes the job the program itself,
/// found on `PATH`, rather than a builtin. The shell's own stderr — job
/// notices such as `Done` — goes to /dev/null; the job gets the real one
/// through fd 3. The `while` loop waits again if `wait` returned while the
/// program is only stopped.
///
/// The shell's stdin is a pipe from the process that started it, which
/// writes nothing to it and keeps it open while the program runs. A watcher
/// reads it: a subshell started before job control is on, so in the shell's
/// own group, which gets the pipe through fd 4 and gives the program none of
/// it — the program's stdin is /dev/null. When the pipe closes — when that
/// process closes it, or ends, however it ends — the watcher tells the shell
/// to stop with SIGTERM. The shell kills the watcher when it exits itself.
/// In `stop`, the watcher is `$!` until `watcher` is set, and before the
/// program starts `end_group $!` finds no group of that id.
///
/// The Dart VM ignores SIGPIPE, and an ignored signal stays ignored through
/// `exec`; a shell cannot undo that. So, when there is `/usr/bin/perl`, the
/// job becomes perl first, which gives SIGPIPE back its default and then
/// becomes the program, found on `PATH` as well: a writer whose reader has
/// exited is killed then, as from a shell. Without perl the program starts
/// with SIGPIPE ignored. perl would warn on stderr — into the step's log —
/// about a `LANG` whose locale is not installed, as Debian images often have
/// it; `PERL_BADLANG=0` keeps it quiet, and perl removes the variable again
/// before it starts the program, which so gets its environment unchanged. The
/// `--` keeps perl from taking a program whose name starts with `-` for a
/// switch of its own.
const inGroupScript =
    _endGroup +
    r'''
stop() {
  trap '' TERM INT HUP
  set +m
  end_group $!
  kill "${watcher:-$!}"
  exit 143
}
[ -x /usr/bin/perl ] && export PERL_BADLANG=0 && set -- /usr/bin/perl -e '
  delete $ENV{PERL_BADLANG};
  $SIG{PIPE} = "DEFAULT";
  exec {$ARGV[0]} @ARGV;
  print STDERR "$ARGV[0]: $!\n";
  exit($!{ENOENT} ? 127 : 126);
' -- "$@"
exec 3>&2 2>/dev/null 4<&0 </dev/null
trap stop TERM INT HUP
{ while read -r line; do :; done; kill -TERM $$; } <&4 >/dev/null 3>&- 4<&- &
watcher=$!
set -m
/bin/sh -c 'echo "nanoflow-exec-group $$" >&2; exec "$@"' sh "$@" \
  2>&3 3>&- 4<&- &
while :; do
  wait $!
  code=$?
  kill -0 $! || break
done
kill $watcher
exit $code
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
final class _Program {
  _Program(this.shell, this.group);

  final Process shell;
  final Future<int?> group;

  /// Whether [_stop] was called for it.
  bool stopped = false;
}
