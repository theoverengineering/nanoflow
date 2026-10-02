import 'dart:io';

/// Whether the app's stdin or stdout is a terminal: then it was started from
/// the user's shell.
///
/// Not [Stdin.hasTerminal]: Dart takes any character device for a terminal,
/// and an app opened from Finder has `/dev/null` for its stdin. Only a
/// terminal has an echo mode to read.
bool attachedToTerminal() => _stdinIsTerminal() || stdout.hasTerminal;

bool _stdinIsTerminal() {
  try {
    stdin.echoMode;
    return true;
  } on StdinException {
    return false;
  }
}
