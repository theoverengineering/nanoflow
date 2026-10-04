// Functions that call themselves or each other: one that does no side effect
// warns nothing; functions in a ring, of two or of three, all reach the first
// side effect a walk from the first of them meets.
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

Future<void> play(Flow f, int n) async {
  rock(n);
  scissors(n);
  await f.effect('play', () => n);
}

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

Future<void> nest(Flow f, int n) async {
  outer(n);
  await f.effect('nest', () => n);
}

/// Calls [middle], and nothing else.
void outer(int n) => middle(n);

/// Calls [inner], which reads the time, then reads the time stamp.
void middle(int n) {
  inner(n);
  print(DateTime.timestamp());
}

/// Reads the time.
void inner(int n) => print(DateTime.now());
