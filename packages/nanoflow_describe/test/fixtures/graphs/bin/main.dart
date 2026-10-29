// Runs the review graph on the branch given as the first argument.
import 'package:nanoflow/nanoflow.dart';

// A fixture has no pubspec.yaml, so its lib/ has no package: URI.
// ignore: avoid_relative_lib_imports
import '../lib/graphs.dart';

Future<void> main(List<String> args) async {
  final flow = Flow();
  await flow.run(review, args.first);
}
