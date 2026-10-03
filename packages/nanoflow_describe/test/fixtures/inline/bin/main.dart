// Publishes the packages given as arguments in each of the four ways.
import 'package:nanoflow/nanoflow.dart';

// A fixture has no pubspec.yaml, so its lib/ has no package: URI.
// ignore: avoid_relative_lib_imports
import '../lib/inline.dart';

Future<void> main(List<String> args) async {
  final flow = Flow();
  await flow.run(inPlace, args);
  await flow.run(viaMap, args);
  await flow.run(viaCall, args);
  await flow.run(sequential, args);
}
