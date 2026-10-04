// Constructors of what the rule names, torn off: each warns where it is torn
// off, as a call of it does.
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';

Future<void> tearOffs(Flow f, List<String> names) async {
  print(names.map(File.new));
  final now = DateTime.now;
  print(now());
  await f.effect('count', () => names.length);
}
