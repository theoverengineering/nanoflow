// The usual ways workflow code runs copies of steps side by side.
import 'dart:math';

import 'package:step_keys/flow.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Copies side by side as an async closure called in place.
Future<void> inPlace(Flow f) async {
  final results = await Future.wait([
    for (final pkg in ['core', 'tool'])
      () async {
        final up = await f.step('upload', () => work('$pkg:uploaded'));
        await pause();
        final ok = await f.step('verify', () => work('$up:verified'));
        await pause();
        return f.step('tag', () => work('$ok:tagged'));
      }(),
  ]);
  note = await f.step('announce', () => work(results.join(' + ')));
}

/// Copies side by side as a closure given to map.
Future<void> viaMap(Flow f) async {
  final results = await Future.wait(
    ['core', 'tool'].map((pkg) async {
      final up = await f.step('upload', () => work('$pkg:uploaded'));
      await pause();
      final ok = await f.step('verify', () => work('$up:verified'));
      await pause();
      return f.step('tag', () => work('$ok:tagged'));
    }),
  );
  note = await f.step('announce', () => work(results.join(' + ')));
}

/// The same body one package after another.
Future<void> sequential(Flow f) async {
  final results = <String>[];
  for (final pkg in ['core', 'tool']) {
    final up = await f.step('upload', () => work('$pkg:uploaded'));
    await pause();
    final ok = await f.step('verify', () => work('$up:verified'));
    await pause();
    results.add(await f.step('tag', () => work('$ok:tagged')));
  }
  note = await f.step('announce', () => work(results.join(' + ')));
}

Future<String> tagIt(Flow f, String ok) async {
  await pause();
  return f.step('tag', () => work('$ok:tagged'));
}

Future<String> publish(Flow f, String pkg) async {
  final up = await f.step('upload', () => work('$pkg:uploaded'));
  await pause();
  final ok = await f.step('verify', () => work('$up:verified'));
  // No await, as the unnecessary_await_in_return lint asks: the stack no
  // longer shows publish inside tagIt.
  return tagIt(f, ok);
}

/// Copies side by side as a function.
Future<void> viaFunction(Flow f) async {
  final results = await Future.wait([
    for (final pkg in ['core', 'tool']) publish(f, pkg),
  ]);
  note = await f.step('announce', () => work(results.join(' + ')));
}

/// Single steps side by side, then one after the join.
Future<void> singleSteps(Flow f) async {
  final results = await Future.wait([
    f.step('publish', () => work('published')),
    f.step('notify', () => work('notified')),
  ]);
  note = await f.step('announce', () => work(results.join(' + ')));
}

void main() {
  checkWorkflow('copies as a closure called in place', inPlace);
  checkWorkflow('copies as a closure given to map', viaMap);
  checkWorkflow('one after another in a for', sequential);
  checkWorkflow('copies as a function returning without await', viaFunction);
  checkWorkflow('single steps side by side', singleSteps);

  test('keys a step after the join in the parent, not in a copy', () async {
    random = Random(1);
    final f = Flow();
    await f.run(viaFunction);
    final announce = f.record.keys.singleWhere((k) => k.endsWith('announce#1'));
    expect(announce, isNot(matches(RegExp('upload|verify|tag'))));
    // And each copy's tag follows its own upload.
    expect(
      f.record.keys.where((k) => k.endsWith('tag#1')),
      everyElement(matches(RegExp(r'upload#\d.*verify#1.*tag#1$'))),
    );
  });
}
