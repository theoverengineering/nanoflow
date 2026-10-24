// Ships the release of the packages named in the arguments.
import 'package:nanoflow/nanoflow.dart';

// A fixture has no pubspec.yaml, so its lib/ has no package: URI.
// ignore: avoid_relative_lib_imports
import '../lib/docs.dart';

Future<void> main(List<String> args) async {
  await Flow().run(release, args);
}
