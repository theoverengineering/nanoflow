import 'dart:io';

import 'package:flutter/services.dart';

/// Runs [executable] with [arguments] to the end.
typedef RunProcess = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// What the app asks of macOS: Finder, the text editor, the app a file of
/// code opens in, and the clipboard. The app runs no programs of the graph:
/// it only reads the graph file and the sessions.
class Shell {
  /// [run] defaults to [Process.run].
  Shell({RunProcess? run}) : _run = run ?? Process.run;

  final RunProcess _run;

  /// The editors that take the line in a link, by their bundle ids: the
  /// link's scheme, `cursor` for `cursor://file/<path>:<line>`.
  static const lineSchemes = {
    'com.microsoft.VSCode': 'vscode',
    'com.microsoft.VSCodeInsiders': 'vscode-insiders',
    'com.vscodium': 'vscodium',
    'com.todesktop.230313mzl4w4u92': 'cursor',
    'com.exafunction.windsurf': 'windsurf',
    'dev.zed.Zed': 'zed',
  };

  /// Asks Launch Services for the bundle id of the app that opens the file
  /// given; prints nothing when no app does.
  static const _appScript = '''
function run(argv) {
  ObjC.import("AppKit");
  const app = \$.NSWorkspace.sharedWorkspace.URLForApplicationToOpenURL(
    \$.NSURL.fileURLWithPath(argv[0]));
  return app.isNil() ? "" : \$.NSBundle.bundleWithURL(app).bundleIdentifier.js;
}''';

  /// Shows [path] selected in a Finder window; false when `open` fails.
  Future<bool> revealInFinder(String path) => _open(['-R', path]);

  /// Opens [path] in the user's default text editor; false when `open`
  /// fails.
  Future<bool> openInEditor(String path) => _open(['-t', path]);

  /// Opens [path] at [line] in the app macOS opens it with, when that app
  /// takes the line in a link ([lineSchemes]); another app opens it at its
  /// top, and with none, the default text editor does. False when there is
  /// no file at [path] or `open` fails.
  Future<bool> openAtLine(String path, int line) async {
    if (!File(path).existsSync()) return false;
    final app = await _appFor(path);
    if (lineSchemes[app] case final scheme?) {
      final link = Uri(scheme: scheme, host: 'file', path: '$path:$line');
      return _open([link.toString()]);
    }
    return app == null ? openInEditor(path) : _open([path]);
  }

  /// The bundle id of the app macOS opens [path] with; `null` when none
  /// does, or when it cannot be asked.
  Future<String?> _appFor(String path) async {
    try {
      final result = await _run('/usr/bin/osascript', [
        '-l',
        'JavaScript',
        '-e',
        _appScript,
        path,
      ]);
      final app = '${result.stdout}'.trim();
      return result.exitCode == 0 && app.isNotEmpty ? app : null;
    } on ProcessException {
      return null;
    }
  }

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
