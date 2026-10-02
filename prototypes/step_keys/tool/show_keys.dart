// Prints the step keys of a few workflows, to look at them.
import 'dart:math';

import 'package:step_keys/flow.dart';

import '../test/implicit_test.dart' as implicit;
import '../test/step_keys_test.dart' as basic;
import '../test/support.dart';

Future<void> main() async {
  for (final (title, workflow) in [
    ('copies as a function', basic.viaFunction),
    ('review loop', implicit.reviewLoop),
    ('copies that begin with a non-step await', implicit.notAStepFirst),
  ]) {
    random = Random(1);
    final f = Flow();
    await f.run(workflow);
    print('$title:\n  ${f.record.keys.join('\n  ')}');
  }
}
