// Every side effect the rule names, in a route: each warns where it is
// written, once for a chain of members. The route is a top-level function.
import 'dart:io';
import 'dart:math';

import 'package:nanoflow/nanoflow.dart';

final before = node('before', (String input) async => input);

final direct = Graph<String, void>('direct', [
  Graph.start(before).next(touchAll),
]);

/// Touches everything the rule names.
Object? touchAll(String input) {
  print(DateTime.now());
  print(DateTime.timestamp());
  print(Stopwatch());
  print(Random());
  print(Random(1));
  print(Random.secure());
  print(File('x').readAsStringSync());
  print(Directory.current);
  print(Platform.environment['HOME']);
  print(Process.runSync('ls', []).stdout);
  print(HttpClient()..autoUncompress = false);
  print(Directory('x').listSync()[0].path);
  exitCode = 1;
  exit(0);
}

final open = node('open', (File file) async => file);

/// Reads the file it is given: a member of a `dart:io` type, called on a
/// parameter.
final given = Graph<File, void>('given', [
  Graph.start(open).next((file) {
    print(file.readAsStringSync());
    return null;
  }),
]);
