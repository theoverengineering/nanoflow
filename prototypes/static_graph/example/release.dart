// What README «Формат» does not show: a loop over data, an if without
// else, a switch, and steps inside a called function.
import 'package:static_graph/flow.dart';

class Package {
  Package(this.name, this.isPublic);
  final String name;
  final bool isPublic;
}

enum Channel { stable, beta, dev }

class Plan {
  Plan(this.packages, this.channel);
  final List<Package> packages;
  final Channel channel;
}

Future<void> release(Flow f, String version) async {
  final plan = await f.step('plan', () => planOf(version));
  for (final pkg in plan.packages) {
    await f.step('build', () => print('build ${pkg.name}'));
    if (pkg.isPublic) await publish(f, pkg);
  }
  switch (plan.channel) {
    case Channel.stable:
      await f.step('announce', () => print('released $version'));
    case Channel.beta:
    case Channel.dev:
      await f.step('notify-testers', () => print('try $version'));
  }
}

/// Uploads [p] and takes it back when it does not verify.
Future<void> publish(Flow f, Package p) async {
  await f.step('upload', () => print('upload ${p.name}'));
  final ok = await f.step('verify', () => p.name.isNotEmpty);
  if (!ok) await f.step('rollback', () => print('rollback ${p.name}'));
}

Plan planOf(String version) =>
    Plan([Package('core', true), Package('tool', false)], Channel.beta);
