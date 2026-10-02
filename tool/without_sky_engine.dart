// Removes package:sky_engine from a package config:
//
//   dart tool/without_sky_engine.dart .dart_tool/package_config.json
//
// The analyzer gives every member of a workspace Flutter's dart: libraries
// once package:sky_engine resolves, and those lack dart:mirrors, which the
// Dart graph library (packages/nanoflow) uses. tool/ci.sh analyzes the Dart
// members with the config without it.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final file = File(args.single);
  final config = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final packages = config['packages']! as List<Object?>;
  packages.removeWhere(
    (package) => (package! as Map<String, Object?>)['name'] == 'sky_engine',
  );
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(config));
}
