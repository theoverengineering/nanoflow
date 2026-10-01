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
    path = p.join(await tempDir(), 'command.log');
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
  });

  group('readLines', () {
    test('gives complete lines without their \\n and leaves an incomplete '
        'last line for later', () async {
      File(path).writeAsStringSync('one\ntwo\nthr');
      final tail = Tail(path);

      expect(await tail.readLines(), [utf8.encode('one'), utf8.encode('two')]);
      expect(await tail.readLines(), isEmpty);
      appendBytes(path, utf8.encode('ee\n\nfour'));
      expect(await tail.readLines(), [utf8.encode('three'), <int>[]]);
    });

    test('gives nothing while the file does not exist', () async {
      expect(await Tail(path).readLines(), isEmpty);
    });

    test('reads on after an incomplete last line is cut off and lines are '
        'appended', () async {
      File(path).writeAsStringSync('one\ntw');
      final tail = Tail(path);
      expect(await tail.readLines(), [utf8.encode('one')]);

      final open = File(path).openSync(mode: FileMode.append);
      open.truncateSync(4);
      open.closeSync();
      appendBytes(path, utf8.encode('two\n'));

      expect(await tail.readLines(), [utf8.encode('two')]);
    });
  });

  group('follow', () {
    // A directory that is never there: only the timer triggers passes.
    late String missing;

    setUp(() async {
      missing = p.join(await tempDir(), 'missing');
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
      while (given.length < 3) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

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
