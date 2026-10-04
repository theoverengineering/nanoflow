// What the graph cannot show, each with a warning where it is: an effect named
// by an expression, effects in a local function and in a closure passed on,
// effects of a function outside the package sources and what a catch does.
import 'package:nanoflow/nanoflow.dart';

import '../other/notify.dart';

Future<void> migrate(Flow f, List<String> tables) async {
  for (final table in tables) {
    await f.effect('copy-$table', () => print('copy $table'));
  }
  Future<void> vacuum(String table) async {
    await f.effect('vacuum', () => print('vacuum $table'));
  }

  await vacuum('events');
  try {
    await f.effect('switch-over', () => print('switch over'));
  } catch (e) {
    await f.effect('switch-back', () => print('switch back: $e'));
  }
  await notifyTeam(f, 'migrated ${tables.length} tables');
}

/// Its only effects are in a closure passed on: a workflow with nothing drawn.
Future<void> check(Flow f, List<String> tables) async {
  await Future.forEach(tables, (table) => f.effect('check', () => table));
}
