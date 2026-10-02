// Prints whether the program runs attached to a terminal, as the app
// decides it; run by terminal_test.dart with its stdin and stdout set up.

import 'dart:io';

import 'package:nanoflow_ui/platform/terminal.dart';

void main() => stderr.write('${attachedToTerminal()}');
