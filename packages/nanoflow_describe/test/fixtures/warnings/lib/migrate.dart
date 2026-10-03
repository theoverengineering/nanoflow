// What the graph cannot show, each with a warning where it is: a step named
// by an expression, steps in a local function and in a closure passed on,
// steps of a function outside the package sources and what a catch does.
import 'package:nanoflow/nanoflow.dart';

import '../other/notify.dart';

Future<void> migrate(Flow f, List<String> tables) async {
  for (final table in tables) {
    await f.step('copy-$table', () => print('copy $table'));
  }
  Future<void> vacuum(String table) async {
    await f.step('vacuum', () => print('vacuum $table'));
  }

  await vacuum('events');
  try {
    await f.step('switch-over', () => print('switch over'));
  } catch (e) {
    await f.step('switch-back', () => print('switch back: $e'));
  }
  await notifyTeam(f, 'migrated ${tables.length} tables');
}

/// Its only steps are in a closure passed on: a workflow with nothing drawn.
Future<void> check(Flow f, List<String> tables) async {
  await Future.forEach(tables, (table) => f.step('check', () => table));
}
