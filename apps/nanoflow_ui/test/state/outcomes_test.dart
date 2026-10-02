import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/state/outcomes.dart';

void main() {
  late Map<String, Completer<Object?>> pending;
  late List<(String, String)> asked;
  late Outcomes outcomes;
  late int notified;

  void run(void Function(FakeAsync async) body) => fakeAsync((async) {
    pending = {};
    asked = [];
    outcomes = Outcomes((sessionId, documentId) {
      asked.add((sessionId, documentId));
      return (pending[documentId] = Completer<Object?>()).future;
    });
    notified = 0;
    outcomes.addListener(() => notified++);
    body(async);
    outcomes.dispose();
    async.flushMicrotasks();
  });

  test('an outcome is unknown until its document is read, then known', () {
    run((async) {
      outcomes.load('s', ['accepted-doc']);
      expect(outcomes['accepted-doc'], isNull);
      pending['accepted-doc']!.complete('accepted');
      async.elapse(const Duration(milliseconds: 50));
      expect(outcomes['accepted-doc'], (value: 'accepted'));
      expect(notified, 1);
    });
  });

  test('an outcome of JSON null is known', () {
    run((async) {
      outcomes.load('s', ['null-doc']);
      pending['null-doc']!.complete(null);
      async.elapse(const Duration(milliseconds: 50));
      expect(outcomes['null-doc'], (value: null));
    });
  });

  test('a document is read once', () {
    run((async) {
      outcomes.load('s', ['doc', 'doc']);
      outcomes.load('s', ['doc']);
      pending['doc']!.complete(true);
      async.elapse(const Duration(milliseconds: 50));
      outcomes.load('s', ['doc']);
      expect(asked, [('s', 'doc')]);
    });
  });

  test('outcomes read together are announced once', () {
    run((async) {
      outcomes.load('s', ['a', 'b', 'c']);
      for (final c in pending.values) {
        c.complete('x');
      }
      async.elapse(const Duration(milliseconds: 50));
      expect(notified, 1);
    });
  });

  test('a document that cannot be read stays unknown, is not read again, '
      'and is reported', () {
    run((async) {
      outcomes.load('s', ['gone']);
      pending['gone']!.completeError(const FormatException('gone.json: bad'));
      async.elapse(const Duration(milliseconds: 50));
      outcomes.load('s', ['gone']);
      expect(outcomes['gone'], isNull);
      expect(asked, hasLength(1));
      expect(outcomes.problems, {'gone': 'FormatException: gone.json: bad'});
      expect(notified, 1);
    });
  });

  test('a read that ends after dispose is dropped', () {
    fakeAsync((async) {
      final done = Completer<Object?>();
      final outcomes = Outcomes((_, _) => done.future)..load('s', ['doc']);
      outcomes.dispose();
      done.complete('late');
      async.elapse(const Duration(milliseconds: 50));
    });
  });
}
