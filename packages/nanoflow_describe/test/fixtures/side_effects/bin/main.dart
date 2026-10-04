// Runs every workflow of the fixture on the first argument.
// A fixture has no pubspec.yaml, so its lib/ has no package: URI.
// ignore_for_file: avoid_relative_lib_imports
import 'package:nanoflow/nanoflow.dart';

import '../lib/calls.dart';
import '../lib/direct.dart';
import '../lib/inside.dart';
import '../lib/logs.dart';
import '../lib/recursion.dart';
import '../lib/tear_offs.dart';
import '../lib/values.dart';

Future<void> main(List<String> args) async {
  final flow = Flow();
  await flow.run(direct, args.first);
  await flow.run(configure, args.first);
  await flow.run(reconfigure, args.first);
  await flow.run(stamp, args.first);
  await flow.run(settle, args.first);
  await flow.run(delegate, args.first);
  await flow.run(handOn, args);
  await flow.run(inside, args.first);
  await flow.run(logs, args.first);
  await flow.run(count, args.first.length);
  await flow.run(serve, args.first.length);
  await flow.run(volley, args.first.length);
  await flow.run(tearOffs, args);
  await flow.run(values, args.first);
}
