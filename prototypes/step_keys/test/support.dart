import 'dart:async';
import 'dart:math';

import 'package:step_keys/flow.dart';
import 'package:test/test.dart';

late Random random;

/// An ordinary await that is not a step, of a random length.
Future<void> pause() =>
    Future.delayed(Duration(milliseconds: random.nextInt(20)));

Future<T> work<T>(T value) async {
  await pause();
  return value;
}

/// What a workflow ended with: wrong when a copy got another's results.
late String note;

/// Tests that [workflow] gives the same keys whatever the timing, and that
/// after a crash at any point every copy gets its own saved results.
void checkWorkflow(String title, Future<void> Function(Flow f) workflow) {
  group(title, () {
    late Flow first;
    late String expected;

    setUp(() async {
      random = Random(1);
      first = Flow();
      await first.run(workflow);
      expected = note;
    });

    test('gives the same keys whatever the timing', () async {
      final keys = first.record.keys.toSet();
      for (var seed = 2; seed < 22; seed++) {
        random = Random(seed);
        final other = Flow();
        await other.run(workflow);
        expect(other.record.keys.toSet(), keys, reason: 'seed $seed');
      }
    });

    test('gives every copy its own saved results after a crash', () async {
      final keys = first.record.keys.toList();
      for (var seed = 2; seed < 22; seed++) {
        random = Random(seed);
        final saved = (keys.toList()..shuffle(random)).take(
          1 + random.nextInt(max(1, keys.length - 1)),
        );
        final resumed = Flow(
          journal: {for (final k in saved) k: first.record[k]},
        );
        await resumed.run(workflow);
        expect(note, expected, reason: 'seed $seed, saved $saved');
      }
    });
  });
}
