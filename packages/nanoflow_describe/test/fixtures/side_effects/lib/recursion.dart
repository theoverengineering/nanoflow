// A function that calls itself and no side effect: reached from a workflow,
// it warns nothing, and the walk through it ends.
import 'package:nanoflow/nanoflow.dart';

Future<void> count(Flow f, int n) async {
  final total = r(n);
  await f.effect('total', () => total);
}

/// Calls itself, and nothing else.
int r(int n) => n <= 0 ? 0 : 1 + r(n - 1);
