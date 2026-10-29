// Functions of the package that routes call and that reach a side effect:
// each call warns where it is, naming the first side effect it reaches.
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';

import 'config.dart';
import 'direct.dart';

final apply = node('apply', (String input) async => input);

final configure = Graph<String, void>('configure', [
  Graph.start(apply).next((input) {
    final config = loadConfig();
    return config.isEmpty ? null : apply(input);
  }),
]);

final reconfigure = Graph<String, void>('reconfigure', [
  Graph.start(apply).next((input) {
    print(input);
    print(loadConfig());
    return null;
  }),
]);

final stamp = Graph<String, void>('stamp', [
  Graph.start(apply).next((input) {
    print(a());
    return null;
  }),
]);

String a() => b();

String b() => '${DateTime.now()}';

final settle = Graph<String, void>('settle', [
  Graph.start(apply).next((input) {
    final settings = Settings();
    print(settings.home);
    print(settings.load());
    settings.home = '/';
    return null;
  }),
]);

/// Reaches side effects through its constructor, accessors and a method.
class Settings {
  Settings() : created = DateTime.now();

  final DateTime created;

  String get home => Platform.environment['HOME'] ?? '';

  set home(String value) => File('home').writeAsStringSync(value);

  String load() => loadConfig();
}

/// Calls a route, whose side effects warn in its own body.
final delegate = Graph<String, void>('delegate', [
  Graph.start(apply).next((input) {
    touchAll(input);
    return null;
  }),
]);

final listed = node('listed', (List<String> names) async => names);

/// Hands a function of the package on without calling it: what the function
/// reaches warns where it is handed on.
final handOn = Graph<List<String>, void>('handOn', [
  Graph.start(listed).next((names) {
    print(names.map(read).length);
    return null;
  }),
]);

String read(String name) => File(name).readAsStringSync();
