// Functions of the package that workflows call and that reach a side effect:
// each call warns where it is, naming the first side effect it reaches.
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';

import 'config.dart';
import 'direct.dart';

Future<void> configure(Flow f, String input) async {
  final config = loadConfig();
  await f.effect('apply', () => '$input $config');
}

Future<void> reconfigure(Flow f, String input) async {
  await f.effect('reset', () => input);
  print(loadConfig());
}

Future<void> stamp(Flow f, String input) async {
  final at = a();
  await f.effect('stamp', () => '$input $at');
}

String a() => b();

String b() => '${DateTime.now()}';

Future<void> settle(Flow f, String input) async {
  final settings = Settings();
  print(settings.home);
  print(settings.load());
  settings.home = '/';
  await f.effect('settle', () => input);
}

/// Reaches side effects through its constructor, accessors and a method.
class Settings {
  Settings() : created = DateTime.now();

  final DateTime created;

  String get home => Platform.environment['HOME'] ?? '';

  set home(String value) => File('home').writeAsStringSync(value);

  String load() => loadConfig();
}

/// Calls a graph function, whose side effects warn in its own body.
Future<void> delegate(Flow f, String input) async {
  await direct(f, input);
}

/// Hands a function of the package on without calling it: what the function
/// reaches warns where it is handed on.
Future<void> handOn(Flow f, List<String> names) async {
  final texts = names.map(read).toList();
  await f.effect('count', () => texts.length);
}

String read(String name) => File(name).readAsStringSync();
