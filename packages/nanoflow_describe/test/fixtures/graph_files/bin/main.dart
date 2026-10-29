// Runs generateIdeas: no graph imports it.
import 'package:nanoflow/nanoflow.dart';

// A fixture has no pubspec.yaml, so its lib/ has no package: URI.
// ignore: avoid_relative_lib_imports
import '../lib/src/generate/generate.dart';

Future<void> main(List<String> args) async {
  await Flow().run(generateIdeas, args.first);
}
