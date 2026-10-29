// Functions that call themselves or each other: one that does no side effect
// warns nothing; functions in a ring, of two or of three, all reach the first
// side effect a walk from the first of them meets.
import 'package:nanoflow/nanoflow.dart';

final total = node('total', (int n) async => n);

final count = Graph<int, void>('count', [
  Graph.start(total).next((n) {
    print(r(n));
    return null;
  }),
]);

/// Calls itself, and nothing else.
int r(int n) => n <= 0 ? 0 : 1 + r(n - 1);

final serve = Graph<int, void>('serve', [
  Graph.start(total).next((n) {
    ping(n);
    return null;
  }),
]);

final volley = Graph<int, void>('volley', [
  Graph.start(total).next((n) {
    pong(n);
    return null;
  }),
]);

/// Calls [pong], then reads the time.
void ping(int n) {
  if (n > 0) pong(n - 1);
  print(DateTime.now());
}

/// Calls [ping] back: it reaches the time through it.
void pong(int n) {
  if (n > 0) ping(n - 1);
}

final play = Graph<int, void>('play', [
  Graph.start(total).next((n) {
    rock(n);
    scissors(n);
    return null;
  }),
]);

/// Calls [paper], then reads the time.
void rock(int n) {
  if (n > 0) paper(n - 1);
  print(DateTime.now());
}

/// Calls [scissors], then reads the time stamp.
void paper(int n) {
  if (n > 0) scissors(n - 1);
  print(DateTime.timestamp());
}

/// Calls [rock]: the ring closes.
void scissors(int n) {
  if (n > 0) rock(n - 1);
}

final nest = Graph<int, void>('nest', [
  Graph.start(total).next((n) {
    outer(n);
    return null;
  }),
]);

/// Calls [middle], and nothing else.
void outer(int n) => middle(n);

/// Calls [inner], which reads the time, then reads the time stamp.
void middle(int n) {
  inner(n);
  print(DateTime.timestamp());
}

/// Reads the time.
void inner(int n) => print(DateTime.now());
