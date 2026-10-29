// `dart run nanoflow_describe`: writes the graph file of every graph of the
// package it runs in, next to its Dart file (file per graph design §3).
import 'dart:io';

import 'package:nanoflow_describe/nanoflow_describe.dart';

Future<void> main(List<String> args) async {
  exitCode = await runDescribe(args, cwd: Directory.current.path);
}
