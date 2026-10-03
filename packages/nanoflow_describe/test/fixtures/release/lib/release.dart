// What the review graph does not show: a loop over data, an if without
// else, a switch on an enum and steps inside a called function.
import 'package:nanoflow/nanoflow.dart';

import 'publish.dart';

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

Plan planOf(String version) =>
    Plan([Package('core', true), Package('tool', false)], Channel.beta);
