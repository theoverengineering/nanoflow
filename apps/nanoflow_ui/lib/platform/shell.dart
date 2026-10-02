import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Runs [executable] with [arguments] to the end.
typedef RunProcess = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// What the app asks of macOS: the user's `PATH`, Finder, the text editor and
/// the clipboard.
class Shell {
  /// [environment] defaults to the app's own; [run] to [Process.run].
  /// [timeout] bounds the login shell asked for `PATH`.
  Shell({
    Map<String, String>? environment,
    RunProcess? run,
    this.timeout = const Duration(seconds: 5),
  }) : _environment = environment ?? Platform.environment,
       _run = run ?? Process.run;

  final Map<String, String> _environment;
  final RunProcess _run;
  final Duration timeout;
  Future<String>? _path;

  /// The user's `PATH` (the plan's decision D15): an app started from Finder
  /// gets only the system's, without what the shell profile adds (Homebrew,
  /// ~/.pub-cache/bin).
  ///
  /// Asked once from the login shell, `$SHELL -l -c 'printf %s "$PATH"'`;
  /// when that fails, the app's own `PATH`.
  Future<String> path() => _path ??= _loginShellPath();

  Future<String> _loginShellPath() async {
    final fallback = _environment['PATH'] ?? '';
    final shell = _environment['SHELL'] ?? '';
    if (shell.isEmpty) return fallback;
    try {
      final process = await Process.start(shell, [
        '-l',
        '-c',
        r'printf %s "$PATH"',
      ]);
      unawaited(process.stdin.close());
      unawaited(process.stderr.drain<void>());
      final output = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      final exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      if (exitCode != 0) return fallback;
      // A profile may print lines of its own before the command runs.
      final path = (await output).split('\n').last;
      return path.isEmpty ? fallback : path;
    } on ProcessException {
      return fallback;
    }
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

  /// Shows [path] selected in a Finder window.
  Future<void> revealInFinder(String path) =>
      _run('/usr/bin/open', ['-R', path]);

  /// Opens [path] in the user's default text editor.
  Future<void> openInEditor(String path) => _run('/usr/bin/open', ['-t', path]);

  Future<void> copyToClipboard(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}
