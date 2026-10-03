// `dart run nanoflow_describe`: writes nanoflow.graph.json in the root of the
// package it runs in (spec §7).
import 'dart:io';

import 'package:nanoflow_describe/nanoflow_describe.dart';

Future<void> main(List<String> args) async {
  exitCode = await runDescribe(args, cwd: Directory.current.path);
}
