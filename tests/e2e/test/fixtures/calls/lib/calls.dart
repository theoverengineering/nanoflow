// Workflows that go on after a call of a function with two effects in a row:
// the effect after it follows the effect before the call, as the library keys
// it (spec §4.3), not the call's last. Through a function, and through a
// closure called in place. tool/record_calls.dart runs them (run_all.dart)
// with the library and records the sessions for the UI's tests of the forks a
// session passed.
import 'package:nanoflow/nanoflow.dart';

Future<String> publish(Flow f, String channel) async {
  final up = await f.effect('upload', () => '$channel:up');
  await f.effect('verify', () => '$up:ok');
  return channel;
}

Future<void> release(Flow f, String channel) async {
  final plan = await f.effect('plan', () => channel);
  await publish(f, plan);
  if (plan == 'stable') {
    await f.effect('announce', () => '$plan announced');
  }
}

Future<void> inPlace(Flow f, String channel) async {
  final plan = await f.effect('plan', () => channel);
  await (() async {
    final up = await f.effect('upload', () => '$plan:up');
    await f.effect('verify', () => '$up:ok');
  })();
  if (plan == 'stable') {
    await f.effect('announce', () => '$plan announced');
  }
}
