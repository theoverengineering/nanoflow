// Every side effect the rule names, between the effects of a workflow and in
// a function with effects: each warns where it is written, once for a chain
// of members.
import 'dart:io';
import 'dart:math';

import 'package:nanoflow/nanoflow.dart';

Future<void> direct(Flow f, String input) async {
  await f.effect('before', () => input);
  print(DateTime.now());
  print(DateTime.timestamp());
  print(Stopwatch());
  print(Random());
  print(Random(1));
  print(Random.secure());
  print(File('x').readAsStringSync());
  print(Directory.current);
  print(Platform.environment['HOME']);
  print((await Process.run('ls', [])).stdout);
  print(HttpClient()..autoUncompress = false);
  print(Directory('x').listSync()[0].path);
  print(HttpStatus.ok);
  exitCode = 1;
  await f.effect('after', () => input);
  exit(0);
}

/// Reads the file it is given: a member of a `dart:io` type, called on a
/// parameter.
Future<void> given(Flow f, File file) async {
  await f.effect('open', () => file.path);
  print(file.readAsStringSync());
}
