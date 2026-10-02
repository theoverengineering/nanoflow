import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Runs [executable] with [arguments] to the end.
typedef RunProcess = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Starts [executable] with [arguments] and leaves it running.
typedef StartProcess = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

/// What the app asks of macOS: the user's `PATH`, Finder, the text editor and
/// the clipboard.
class Shell {
  /// [environment] defaults to the app's own; [run] to [Process.run];
  /// [start] to [Process.start]; [terminal] to whether the app's stdin or
  /// stdout is a terminal. [timeout] bounds each shell asked for `PATH`.
  Shell({
    Map<String, String>? environment,
    RunProcess? run,
    StartProcess? start,
    bool? terminal,
    this.timeout = const Duration(seconds: 5),
  }) : _terminal = terminal ?? (stdin.hasTerminal || stdout.hasTerminal),
       _environment = environment ?? Platform.environment,
       _run = run ?? Process.run,
       _start = start ?? Process.start;

  final bool _terminal;
  final Map<String, String> _environment;
  final RunProcess _run;
  final StartProcess _start;
  final Duration timeout;
  Future<String>? _path;

  /// The user's `PATH` (the plan's decision D15): an app started from Finder
  /// gets only the system's, without what the shell profile adds (Homebrew,
  /// ~/.pub-cache/bin).
  ///
  /// Asked once from the user's shell as an interactive login shell,
  /// `$SHELL -i -l -c …`, so that zsh reads `~/.zshrc` too, where
  /// `~/.pub-cache/bin` usually goes; when that fails, as a login shell only,
  /// `$SHELL -l -c …`; when that fails too, the app's own `PATH`. The shell
  /// prints `PATH` on a line after [_marker], so whatever the profile prints
  /// around it does not matter. An app attached to a terminal uses its own
  /// `PATH` at once: it is the user's.
  Future<String> path() => _path ??= _userPath();

  /// What the shell prints in front of `PATH`.
  static const _marker = '__NANOFLOW_PATH__=';

  Future<String> _userPath() async {
    final fallback = _environment['PATH'] ?? '';
    final shell = _environment['SHELL'] ?? '';
    // Started from a terminal (`flutter run`), the app has the user's PATH
    // already, and an interactive shell could take the terminal over.
    if (_terminal || shell.isEmpty) return fallback;
    for (final flags in const [
      ['-i', '-l'],
      ['-l'],
    ]) {
      final path = await _askShell(shell, flags);
      if (path != null && path.isNotEmpty) return path;
    }
    return fallback;
  }

  /// The `PATH` [shell] started with [flags] prints, or `null`.
  ///
  /// Waits at most [timeout] in all: a profile may hang, or leave a program
  /// running that holds the shell's output open after the shell has exited.
  Future<String?> _askShell(String shell, List<String> flags) async {
    final Process process;
    try {
      process = await _start(shell, [
        ...flags,
        '-c',
        'printf "\\n$_marker%s\\n" "\$PATH"',
      ]);
    } on ProcessException {
      return null;
    }
    // A profile that asks something reads an end of input instead.
    process.stdin.close().ignore();
    final output = StringBuffer();
    final printed = Completer<void>();
    void finish() {
      if (!printed.isCompleted) printed.complete();
    }

    final out = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (chunk) {
            output.write(chunk);
            if (_pathIn(output.toString()) != null) finish();
          },
          onError: (Object _) => finish(),
          onDone: finish,
        );
    final err = process.stderr.listen(null, onError: (Object _) {});
    try {
      await printed.future.timeout(timeout, onTimeout: () {});
    } finally {
      process.kill(ProcessSignal.sigkill);
      unawaited(out.cancel());
      unawaited(err.cancel());
    }
    return _pathIn(output.toString());
  }

  /// The `PATH` on the last complete line that starts with [_marker].
  static String? _pathIn(String output) {
    final lines = output.split('\n');
    // The last piece has no newline yet.
    for (final line in lines.take(lines.length - 1).toList().reversed) {
      if (line.startsWith(_marker)) return line.substring(_marker.length);
    }
    return null;
  }

  /// The first executable file [name] in the directories of [path].
  Future<String?> findExecutable(String name) async {
    for (final dir in (await path()).split(':')) {
      if (dir.isEmpty) continue;
      final candidate = '$dir/$name';
      final stat = await FileStat.stat(candidate);
      if (stat.type == FileSystemEntityType.file && stat.mode & 0x49 != 0) {
        return candidate;
      }
    }
    return null;
  }

  /// Starts [executable] with the user's [path] as its `PATH` and leaves it
  /// running: programs the app starts find what the user's terminal finds.
  ///
  /// The program runs in a process group of its own, so that [Process.kill]
  /// stops it with every process it started: a `nanoflow-yaml` installed by
  /// `dart pub global activate` is a script that starts `dart`, which would
  /// otherwise go on running. Its stdin, stdout, stderr and exit code are the
  /// program's.
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async => _start(
    '/bin/sh',
    ['-c', groupScript, 'sh', executable, ...arguments],
    workingDirectory: workingDirectory,
    environment: {'PATH': await path()},
  );

  /// The `/bin/sh -c` script that runs a program — `"$@"` — in a process
  /// group of its own, and sends SIGTERM to the group when the shell gets
  /// SIGTERM, SIGINT or SIGHUP, or when the app that started it is gone:
  /// quitting the app does not dispose what it shows, and a crash would not
  /// either. Otherwise it exits with the program's code.
  ///
  /// With job control (`set -m`) the program, started in the background,
  /// leads a new process group and keeps the shell's stdin; bash — `/bin/sh`
  /// on macOS — keeps job control on without a terminal. The shell's own
  /// stderr (job notices) goes to /dev/null; the program gets the real one
  /// through fd 3. A watchdog in the background looks for the app once a
  /// second, holding none of the program's pipes.
  @visibleForTesting
  static const groupScript = r'''
exec 3>&2 2>/dev/null
trap 'kill -TERM -$job; kill $watchdog; exit 143' TERM INT HUP
set -m
exec "$@" 2>&3 3>&- &
job=$!
set +m
app=$PPID
(
  while kill -0 "$app"; do sleep 1; done
  kill -TERM -"$job"
) </dev/null >/dev/null 3>&- &
watchdog=$!
wait "$job"
code=$?
kill "$watchdog"
exit "$code"
''';

  /// Shows [path] selected in a Finder window; false when `open` fails.
  Future<bool> revealInFinder(String path) => _open(['-R', path]);

  /// Opens [path] in the user's default text editor; false when `open`
  /// fails.
  Future<bool> openInEditor(String path) => _open(['-t', path]);

  Future<bool> _open(List<String> arguments) async {
    try {
      return (await _run('/usr/bin/open', arguments)).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  Future<void> copyToClipboard(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}
