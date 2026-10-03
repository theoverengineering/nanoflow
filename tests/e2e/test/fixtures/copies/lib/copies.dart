// Workflows that run copies of steps side by side, the ways the prototype
// step_keys covers: an async closure called in place, a closure given to
// map, a function called for each item, and copies in copies. The steps
// wait for different times, so that the copies interleave.
// tool/record_copies.dart runs them (run_all.dart) with the library and
// records the sessions for the UI's tests of copies.
import 'package:nanoflow/nanoflow.dart';

/// How long [what] of [item] takes: uneven, so that copies interleave.
Future<String> work(String item, String what, int ms) async {
  await Future<void>.delayed(Duration(milliseconds: ms));
  return '$item:$what';
}

const packages = ['core', 'tool', 'cli'];

const targets = ['arm', 'x64'];

/// How long a step of [pkg] waits, in milliseconds, [step] from 0.
int wait(String pkg, int step) => 5 + 7 * ((packages.indexOf(pkg) + step) % 3);

Future<String> inPlace(Flow f, List<String> items) async {
  final plan = await f.step('plan', () => items.join(','));
  final results = await Future.wait([
    for (final pkg in plan.split(','))
      () async {
        final up = await f.step('upload', () => work(pkg, 'up', wait(pkg, 0)));
        final ok = await f.step('verify', () => work(up, 'ok', wait(pkg, 1)));
        return f.step('tag', () => work(ok, 'tag', wait(pkg, 2)));
      }(),
  ]);
  return f.step('announce', () => results.join(' + '));
}

Future<String> viaMap(Flow f, List<String> items) async {
  final results = await Future.wait(
    items.map((pkg) async {
      final up = await f.step('upload', () => work(pkg, 'up', wait(pkg, 0)));
      final ok = await f.step('verify', () => work(up, 'ok', wait(pkg, 1)));
      return f.step('tag', () => work(ok, 'tag', wait(pkg, 2)));
    }),
  );
  return f.step('announce', () => results.join(' + '));
}

Future<String> publish(Flow f, String pkg) async {
  final up = await f.step('upload', () => work(pkg, 'up', wait(pkg, 0)));
  final ok = await f.step('verify', () => work(up, 'ok', wait(pkg, 1)));
  return f.step('tag', () => work(ok, 'tag', wait(pkg, 2)));
}

Future<String> viaCall(Flow f, List<String> items) async {
  final results = await Future.wait([for (final pkg in items) publish(f, pkg)]);
  return f.step('announce', () => results.join(' + '));
}

Future<String> nested(Flow f, List<String> items) async {
  final results = await Future.wait([
    for (final pkg in items)
      () async {
        final src = await f.step('fetch', () => work(pkg, 'src', wait(pkg, 0)));
        final builds = await Future.wait([
          for (final target in targets)
            () async {
              final bin = await f.step(
                'build',
                () => work(
                  '$src/$target',
                  'bin',
                  wait(pkg, targets.indexOf(target)),
                ),
              );
              return f.step('test', () => work(bin, 'ok', wait(pkg, 1)));
            }(),
        ]);
        return f.step('upload', () => builds.join('|'));
      }(),
  ]);
  return f.step('announce', () => results.join(' + '));
}
