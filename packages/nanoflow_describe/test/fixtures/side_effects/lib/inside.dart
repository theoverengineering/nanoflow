// Side effects in effects, in functions only an effect calls and in effects
// of the functions a workflow calls: none warns.
import 'dart:io';
import 'dart:math';

import 'package:nanoflow/nanoflow.dart';

import 'config.dart';

Future<void> inside(Flow f, String input) async {
  final text = await f.effect('read', () => File('a').readAsStringSync());
  await f.effect('everything', () async {
    print(DateTime.now());
    print(Random.secure());
    print(Platform.environment['HOME']);
    print(await Process.run('ls', []));
    print(loadConfig());
  });
  await f.effect('save', () => save('$input $text'));
  print(await readIn(f));
  Future<String> load() => f.effect('load', () => File('d').readAsStringSync());
  print(await load());
  String now() => '${DateTime.now()}';
  await f.effect('now', () => now());
}

/// Writes a file; only an effect calls it.
void save(String text) => File('b').writeAsStringSync(text);

/// Reads a file in an effect of its own.
Future<String> readIn(Flow f) =>
    f.effect('read-in', () => File('c').readAsStringSync());
