// Functions that call themselves or each other: one that does no side effect
// warns nothing, and the walk through it ends; ones that call each other reach
// the side effect either of them meets, whichever a workflow calls first.
import 'package:nanoflow/nanoflow.dart';

Future<void> count(Flow f, int n) async {
  final total = r(n);
  await f.effect('total', () => total);
}

/// Calls itself, and nothing else.
int r(int n) => n <= 0 ? 0 : 1 + r(n - 1);

Future<void> serve(Flow f, int n) async {
  ping(n);
  await f.effect('serve', () => n);
}

Future<void> volley(Flow f, int n) async {
  pong(n);
  await f.effect('volley', () => n);
}

/// Calls [pong], then reads the time.
void ping(int n) {
  if (n > 0) pong(n - 1);
  print(DateTime.now());
}

/// Calls [ping] back: it reaches the time through it.
void pong(int n) {
  if (n > 0) ping(n - 1);
}
