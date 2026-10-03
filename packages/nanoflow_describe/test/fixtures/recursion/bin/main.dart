// Deploys, then crawls the site given as the first argument.
import 'package:nanoflow/nanoflow.dart';

// A fixture has no pubspec.yaml, so its lib/ has no package: URI.
// ignore: avoid_relative_lib_imports
import '../lib/crawl.dart';

Future<void> main(List<String> args) async {
  final flow = Flow();
  await flow.run(deploy, 1);
  await flow.run(crawl, args.first);
}
