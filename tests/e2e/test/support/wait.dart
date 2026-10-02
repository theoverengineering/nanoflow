import 'package:test/test.dart';

/// Waits until [condition] holds; after 20 s fails the test, saying it
/// waited for [what].
Future<void> waitFor(String what, bool Function() condition) async {
  for (var i = 0; i < 400; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('timed out waiting for $what');
}
