import 'dart:io';

import 'package:nanoflow_cli/nanoflow_cli.dart';

/// `nanoflow` with the arguments, as `bin/nanoflow.dart` runs it; then one
/// more line on stderr says whether fd 0 is still open: `fd 0 open` or
/// `fd 0 closed`.
Future<void> main(List<String> args) async {
  exitCode = await runCli(args);
  final fd0 = FileSystemEntity.typeSync('/dev/fd/0', followLinks: false);
  stderr.writeln(
    fd0 == FileSystemEntityType.notFound ? 'fd 0 closed' : 'fd 0 open',
  );
}
