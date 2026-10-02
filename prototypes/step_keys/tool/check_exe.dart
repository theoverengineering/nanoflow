// The test scenarios without package:test, to compile with
// `dart compile exe` and check the keys in AOT code too.
import 'dart:io';
import 'dart:math';

import 'package:step_keys/flow.dart';

import '../test/implicit_test.dart' as implicit;
import '../test/step_keys_test.dart' as basic;
import '../test/support.dart';

Future<void> main() async {
  final workflows = <String, Future<void> Function(Flow)>{
    'in place': basic.inPlace,
    'via map': basic.viaMap,
    'sequential': basic.sequential,
    'via function': basic.viaFunction,
    'single steps': basic.singleSteps,
    'nested copies': implicit.nestedCopies,
    'review loop': implicit.reviewLoop,
    'identical results': implicit.identicalResults,
    'awaited later': implicit.awaitedLater,
    'caught failure': implicit.caughtFailure,
    'recursion': implicit.recursion,
    'await for': implicit.overStream,
    'staggered start': implicit.staggeredStart,
    'not a step first': implicit.notAStepFirst,
  };
  var failed = false;
  for (final MapEntry(key: title, value: workflow) in workflows.entries) {
    random = Random(1);
    final first = Flow();
    await first.run(workflow);
    final expected = note;
    final keys = first.record.keys.toSet();
    var sameKeys = 0, rightData = 0;
    for (var seed = 2; seed < 22; seed++) {
      random = Random(seed);
      final other = Flow();
      await other.run(workflow);
      if (other.record.keys.toSet().containsAll(keys) &&
          keys.containsAll(other.record.keys)) {
        sameKeys++;
      }
      final saved = (keys.toList()..shuffle(random)).take(
        1 + random.nextInt(max(1, keys.length - 1)),
      );
      final resumed = Flow(
        journal: {for (final k in saved) k: first.record[k]},
      );
      await resumed.run(workflow);
      if (note == expected) rightData++;
    }
    failed |= sameKeys < 20 || rightData < 20;
    print('${title.padRight(18)} keys $sameKeys/20  data $rightData/20');
  }
  exitCode = failed ? 1 : 0;
}
