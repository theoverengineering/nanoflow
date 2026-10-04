// Not under lib/ or bin/: outside the package sources, so where it is called
// its effects are not drawn.
import 'package:nanoflow/nanoflow.dart';

Future<void> notifyTeam(Flow f, String text) async {
  await f.effect('notify', () => print(text));
}
