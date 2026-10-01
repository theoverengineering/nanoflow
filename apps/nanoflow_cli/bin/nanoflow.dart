import 'dart:io';

import 'package:nanoflow_cli/nanoflow_cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await runCli(args);
}
