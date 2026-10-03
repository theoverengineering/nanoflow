// Migrates the tables given as arguments, then checks them.
import 'package:nanoflow/nanoflow.dart';

// A fixture has no pubspec.yaml, so its lib/ has no package: URI.
// ignore: avoid_relative_lib_imports
import '../lib/migrate.dart';

Future<void> main(List<String> args) async {
  final flow = Flow();
  await flow.run(migrate, args);
  await flow.run(check, args);
}
