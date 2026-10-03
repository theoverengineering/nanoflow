import 'dart:io';

import 'package:flutter/services.dart';

/// Runs [executable] with [arguments] to the end.
typedef RunProcess = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// What the app asks of macOS: Finder, the text editor and the clipboard.
/// The app runs no programs of the graph: it only reads the graph file and
/// the sessions.
class Shell {
  /// [run] defaults to [Process.run].
  Shell({RunProcess? run}) : _run = run ?? Process.run;

  final RunProcess _run;

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
