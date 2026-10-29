// Side effects in nodes, and in functions only a node calls: none warns.
import 'dart:io';
import 'dart:math';

import 'package:nanoflow/nanoflow.dart';

import 'config.dart';

final everything = node('everything', (String input) async {
  print(DateTime.now());
  print(Random.secure());
  print(Platform.environment['HOME']);
  print(await Process.run('ls', []));
  print(loadConfig());
  save(input);
  return File('a').readAsStringSync();
});

/// Writes a file; only a node calls it.
void save(String text) => File('b').writeAsStringSync(text);

final inside = Graph<String, void>('inside', [
  Graph.start(everything).next((text) => null),
]);
