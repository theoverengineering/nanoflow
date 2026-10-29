// Constructors of what the rule names, torn off: each warns where it is torn
// off, as a call of it does.
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';

final names = node('names', (List<String> names) async => names);

final tearOffs = Graph<List<String>, void>('tearOffs', [
  Graph.start(names).next((names) {
    print(names.map(File.new));
    final now = DateTime.now;
    print(now());
    return null;
  }),
]);
