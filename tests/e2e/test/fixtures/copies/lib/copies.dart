// Workflows that run copies of effects side by side, the ways the prototype
// step_keys covers: an async closure called in place, a closure given to
// map, a function called for each item, and copies in copies. The effects
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

/// How long an effect of [pkg] waits, in milliseconds, [effect] from 0.
int wait(String pkg, int effect) =>
    5 + 7 * ((packages.indexOf(pkg) + effect) % 3);

Future<String> inPlace(Flow f, List<String> items) async {
  final plan = await f.effect('plan', () => items.join(','));
  final results = await Future.wait([
    for (final pkg in plan.split(','))
      () async {
        final up = await f.effect(
          'upload',
          () => work(pkg, 'up', wait(pkg, 0)),
        );
        final ok = await f.effect('verify', () => work(up, 'ok', wait(pkg, 1)));
        return f.effect('tag', () => work(ok, 'tag', wait(pkg, 2)));
      }(),
  ]);
  return f.effect('announce', () => results.join(' + '));
}

Future<String> viaMap(Flow f, List<String> items) async {
  final results = await Future.wait(
    items.map((pkg) async {
      final up = await f.effect('upload', () => work(pkg, 'up', wait(pkg, 0)));
      final ok = await f.effect('verify', () => work(up, 'ok', wait(pkg, 1)));
      return f.effect('tag', () => work(ok, 'tag', wait(pkg, 2)));
    }),
  );
  return f.effect('announce', () => results.join(' + '));
}

Future<String> publish(Flow f, String pkg) async {
  final up = await f.effect('upload', () => work(pkg, 'up', wait(pkg, 0)));
  final ok = await f.effect('verify', () => work(up, 'ok', wait(pkg, 1)));
  return f.effect('tag', () => work(ok, 'tag', wait(pkg, 2)));
}

Future<String> viaCall(Flow f, List<String> items) async {
  final results = await Future.wait([for (final pkg in items) publish(f, pkg)]);
  return f.effect('announce', () => results.join(' + '));
}

Future<String> nested(Flow f, List<String> items) async {
  final results = await Future.wait([
    for (final pkg in items)
      () async {
        final src = await f.effect(
          'fetch',
          () => work(pkg, 'src', wait(pkg, 0)),
        );
        final builds = await Future.wait([
          for (final target in targets)
            () async {
              final bin = await f.effect(
                'build',
                () => work(
                  '$src/$target',
                  'bin',
                  wait(pkg, targets.indexOf(target)),
                ),
              );
              return f.effect('test', () => work(bin, 'ok', wait(pkg, 1)));
            }(),
        ]);
        return f.effect('upload', () => builds.join('|'));
      }(),
  ]);
  return f.effect('announce', () => results.join(' + '));
}
