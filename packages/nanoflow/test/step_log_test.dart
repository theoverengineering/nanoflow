import 'dart:async';
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

/// Prints before, between and after two steps that run side by side and
/// print in turns.
Future<String> printsSideBySide(Flow f, String x) async {
  print('before the steps');
  final both = await Future.wait([
    for (final side in ['left', 'right'])
      f.step(side, () async {
        print('$side 1');
        await Future<void>.delayed(Duration.zero);
        print('$side 2');
        return side;
      }),
  ]);
  print('after the steps');
  return both.join(' ');
}

/// Prints in a step, in a step called in its body, and after it.
Future<String> printsNested(Flow f, String x) => f.step('outer', () async {
  print('outer 1');
  await f.step('inner', () => print('inner'));
  print('outer 2');
  return 'nested';
});

/// A step whose body prints, if [loud], before its first await, and then
/// calls a step.
Future<String> printsBeforeStep(Flow f, bool loud) => f.step('outer', () async {
  if (loud) print('loud');
  await Future<void>.delayed(Duration.zero);
  return f.step('inner', () => 'quiet');
});

/// Opened to let the step of [printsAfterGate] print.
late Completer<void> gate;

/// Completed when the step of [printsAfterGate] waits for [gate].
late Completer<void> atGate;

/// Its step prints once [gate] is opened.
Future<String> printsAfterGate(Flow f, String x) => f.step('late', () async {
  atGate.complete();
  await gate.future;
  print('after the gate');
  return 'printed';
});

/// Completes once the line the step of [printsLate] leaves behind is printed.
late Completer<void> printedLate;

/// Its step leaves a timer behind that prints once the step has ended.
Future<String> printsLate(Flow f, String x) async {
  await f.step('early', () {
    Timer(const Duration(milliseconds: 20), () {
      print('late');
      printedLate.complete();
    });
  });
  return 'left';
}

/// Runs [workflow] in [dir] and gives what it printed outside its steps.
Future<List<String>> printedOutside(
  String dir,
  Future<String> Function(Flow f, String x) workflow, {
  Future<void>? until,
}) async {
  final printed = <String>[];
  await runZoned(
    () async {
      await Flow(directory: dir).run(workflow, 'x');
      await until;
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => printed.add(line),
    ),
  );
  return printed;
}

void main() {
  test('print in a step body goes to the log of that step, even with another '
      'step printing at the same time; print outside the steps does '
      'not', () async {
    final dir = await tempDir();

    expect(await printedOutside(dir, printsSideBySide), [
      'before the steps',
      'after the steps',
    ]);

    final handle = await onlySession(dir);
    expect(await logOfStep(handle, 'left'), 'left 1\nleft 2\n');
    expect(await logOfStep(handle, 'right'), 'right 1\nright 2\n');
  });

  test('print in a step called in a step body goes to the log of the step '
      'it is in', () async {
    final dir = await tempDir();

    expect(await printedOutside(dir, printsNested), isEmpty);

    final handle = await onlySession(dir);
    expect(await logOfStep(handle, 'outer'), 'outer 1\nouter 2\n');
    expect(await logOfStep(handle, 'inner'), 'inner\n');
  });

  test('print moves no step key', () async {
    final dir = await tempDir();
    final flow = Flow(directory: dir);
    final keys = <bool, List<String>>{};

    for (final loud in [false, true]) {
      final session = await flow.start(printsBeforeStep, loud);
      await session.result;
      keys[loud] = [
        for (final step in await (await openSession(dir, session.id)).steps())
          step.key,
      ];
    }

    expect(keys[true], keys[false]);
  });

  test('a log that cannot be written is a failure of the store: the step '
      'fails with a StorageException, which is the result, and nothing more '
      'is written', () async {
    final dir = await tempDir();
    gate = Completer();
    atGate = Completer();
    final session = await Flow(directory: dir).start(printsAfterGate, 'x');
    await atGate.future;

    final steps = p.join(sessionDirOf(dir, session.id), stepsDirName);
    for (final step in Directory(steps).listSync()) {
      step.deleteSync(recursive: true);
    }
    gate.complete();

    await expectLater(session.result, throwsA(isA<StorageException>()));
    expect(eventNamesOf(dir, session.id), ['session-started', 'step-started']);
  });

  test('print once the flow is stopped goes to the process print: nothing '
      'more is written to the session', () async {
    final dir = await tempDir();
    gate = Completer();
    atGate = Completer();
    final printed = <String>[];
    final flow = Flow(directory: dir);
    final session = await runZoned(
      () => flow.start(printsAfterGate, 'x'),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => printed.add(line),
      ),
    );
    await atGate.future;

    flow.stop();
    gate.complete();

    await expectLater(session.result, throwsA(isA<FlowStoppedException>()));
    expect(printed, ['after the gate']);
    expect(await logOfStep(await onlySession(dir), 'late'), isNull);
  });

  test('print from a step body after the step has ended goes to the process '
      'print', () async {
    final dir = await tempDir();
    printedLate = Completer();

    expect(await printedOutside(dir, printsLate, until: printedLate.future), [
      'late',
    ]);

    expect(await logOfStep(await onlySession(dir), 'early'), isNull);
  });
}
