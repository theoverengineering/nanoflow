import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:nanoflow_reader/src/tail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late String path;

  setUp(() async {
    path = p.join(await tempDir(), 'step.log');
  });

  group('read', () {
    test(
      'gives nothing while the file does not exist, then all of it',
      () async {
        final tail = Tail(path);

        expect(await tail.read(), isEmpty);
        File(path).writeAsStringSync('hello\n');
        expect(await tail.read(), utf8.encode('hello\n'));
      },
    );

    test('gives what was appended since the last read', () async {
      File(path).writeAsStringSync('one');
      final tail = Tail(path);

      expect(await tail.read(), utf8.encode('one'));
      expect(await tail.read(), isEmpty);
      appendBytes(path, utf8.encode(' two'));
      expect(await tail.read(), utf8.encode(' two'));
      appendBytes(path, [0xc3]);
      expect(await tail.read(), [0xc3]);
    });

    test('reads on from the new end of a file that got shorter', () async {
      File(path).writeAsStringSync('hello');
      final tail = Tail(path);
      expect(await tail.read(), utf8.encode('hello'));

      truncate(path, 2);
      expect(await tail.read(), isEmpty);
      appendBytes(path, utf8.encode('y!'));

      expect(await tail.read(), utf8.encode('y!'));
    });
  });

  group('readLines', () {
    /// The lines [tail] gives, as numbers and text.
    Future<List<(int, String)>> lines(Tail tail) async => [
      for (final (:number, :bytes) in await tail.readLines())
        (number, utf8.decode(bytes)),
    ];

    test('gives complete lines without their \\n, numbered from 1, and '
        'leaves an incomplete last line for later', () async {
      File(path).writeAsStringSync('one\ntwo\nthr');
      final tail = Tail(path);

      expect(await lines(tail), [(1, 'one'), (2, 'two')]);
      expect(await lines(tail), isEmpty);
      appendBytes(path, utf8.encode('ee\n\nfour'));
      expect(await lines(tail), [(3, 'three'), (4, '')]);
    });

    test('gives nothing while the file does not exist', () async {
      expect(await Tail(path).readLines(), isEmpty);
    });

    test('reads on after an incomplete last line is cut off and lines are '
        'appended', () async {
      File(path).writeAsStringSync('one\ntw');
      final tail = Tail(path);
      expect(await lines(tail), [(1, 'one')]);

      truncate(path, 4);
      appendBytes(path, utf8.encode('two\n'));

      expect(await lines(tail), [(2, 'two')]);
    });

    test('reads on after the last complete line left in a file that got '
        'shorter than the lines given', () async {
      File(path).writeAsStringSync('one\ntwo\nthree\n');
      final tail = Tail(path);
      expect(await lines(tail), [(1, 'one'), (2, 'two'), (3, 'three')]);

      truncate(path, 6);
      expect(await lines(tail), isEmpty);
      appendBytes(path, utf8.encode('o\nfour\n'));

      expect(await lines(tail), [(2, 'two'), (3, 'four')]);
    });
  });

  group('follow', () {
    // A directory that is never there: only the timer, and wake, trigger
    // passes.
    late String missing;

    setUp(() async {
      missing = p.join(await tempDir(), 'missing');
    });

    test('passes on every event of wake, and stops listening to it once '
        'cancelled', () async {
      final wake = StreamController<void>();
      var passes = 0;
      final followed = follow<int>(
        missing,
        recursive: false,
        interval: const Duration(hours: 1),
        wake: wake.stream,
        pass: (out) async => out.add(++passes),
      );
      final given = <int>[];
      final subscription = followed.listen(given.add);
      await eventually(() => given.isNotEmpty);

      wake.add(null);
      await eventually(() => given.length == 2);
      await subscription.cancel();

      expect(given, [1, 2]);
      expect(wake.hasListener, isFalse);
    });

    test('never runs two passes at once', () async {
      final firstDone = Completer<void>();
      var passes = 0;
      var running = 0;
      var mostRunning = 0;
      final followed = follow<int>(
        missing,
        recursive: false,
        interval: const Duration(milliseconds: 5),
        pass: (out) async {
          passes++;
          mostRunning = max(mostRunning, ++running);
          if (passes == 1) await firstDone.future;
          running--;
          out.add(passes);
        },
      );
      final given = <int>[];
      final subscription = followed.listen(given.add);
      addTearDown(subscription.cancel);

      // The timer fires a few times during the first pass.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(passes, 1);
      firstDone.complete();
      await eventually(() => given.length >= 3);

      expect(mostRunning, 1);
      expect(given.take(3), [1, 2, 3]);
    });

    test('gives an error a pass throws to the stream and goes on', () async {
      var passes = 0;
      final followed = follow<int>(
        missing,
        recursive: false,
        interval: const Duration(milliseconds: 5),
        pass: (out) async {
          if (++passes == 1) throw StateError('first');
          out.add(passes);
        },
      );

      await expectLater(followed, emitsInOrder([emitsError(isStateError), 2]));
    });

    test('runs no pass once cancelled before the first one began', () async {
      var passes = 0;
      final followed = follow<void>(
        missing,
        recursive: false,
        interval: const Duration(milliseconds: 5),
        pass: (out) async => passes++,
      );

      // Cancelled while the first pass looks for the directory to watch.
      await followed.listen((_) {}).cancel();

      expect(passes, 0);
    });

    test('once cancelled, ends the pass under way and runs no other', () async {
      final firstDone = Completer<void>();
      var passes = 0;
      final followed = follow<int>(
        missing,
        recursive: false,
        interval: const Duration(milliseconds: 5),
        pass: (out) async {
          if (++passes == 1) await firstDone.future;
        },
      );
      final subscription = followed.listen((_) {});
      // The timer fires during the first pass, asking for one more.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      var cancelled = false;
      final cancelling = subscription.cancel().then((_) => cancelled = true);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(cancelled, isFalse);
      firstDone.complete();
      await cancelling;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(passes, 1);
    });
  });
}
