// Deploys the service given as the first argument.
import 'package:nanoflow/nanoflow.dart';

// A fixture has no pubspec.yaml, so its lib/ has no package: URI.
// ignore: avoid_relative_lib_imports
import '../lib/deploy.dart';

Future<void> main(List<String> args) async {
  await Flow().run(deploy, args.first);
}
