import 'dart:convert';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:test/test.dart';

final DateTime _started = DateTime.utc(2026, 10, 3, 7, 43, 34, 651);
const String _startedText = '2026-10-03T07:43:34.651Z';

Map<String, Object?> _decode(String text) =>
    jsonDecode(text) as Map<String, Object?>;

/// The message of the [FormatException] thrown by [read].
String _problem(void Function() read) {
  try {
    read();
  } on FormatException catch (e) {
    return e.message;
  }
  throw StateError('Expected a FormatException');
}

void main() {
  group('Owner', () {
    final owner = Owner(pid: 4242, started: _started);
    const text = '{"pid":4242,"started":"$_startedText"}';

    test('writes pid, then started in the event time format', () {
      expect(jsonEncode(owner.toJson()), text);
      expect(owner.toJson().keys, ['pid', 'started']);
    });

    test('writes an unknown start time as null, keeping the key', () {
      const unknown = Owner(pid: 4242, started: null);

      expect(jsonEncode(unknown.toJson()), '{"pid":4242,"started":null}');
    });

    test('round trips', () {
      final read = Owner.fromJson(_decode(text));

      expect(read, owner);
      expect(read.hashCode, owner.hashCode);
      expect(read.pid, 4242);
      expect(read.started, _started);
      expect(read.started!.isUtc, isTrue);
      expect(jsonEncode(read.toJson()), text);
    });

    test('round trips an unknown start time', () {
      const unknown = Owner(pid: 4242, started: null);
      final read = Owner.fromJson(_decode('{"pid":4242,"started":null}'));

      expect(read, unknown);
      expect(read.started, isNull);
      expect(jsonEncode(read.toJson()), '{"pid":4242,"started":null}');
    });

    test('compares by pid and start time', () {
      expect(owner, Owner(pid: 4242, started: _started));
      expect(owner, isNot(Owner(pid: 4243, started: _started)));
      expect(
        owner,
        isNot(
          Owner(
            pid: 4242,
            started: _started.add(const Duration(milliseconds: 1)),
          ),
        ),
      );
      expect(owner, isNot(const Owner(pid: 4242, started: null)));
      expect(const Owner(pid: 4242, started: null), isNot(owner));
      expect(
        const Owner(pid: 4242, started: null),
        const Owner(pid: 4242, started: null),
      );
    });

    test('is the same owner whatever the zone or the sub-millisecond part', () {
      // The file keeps UTC and milliseconds, so this is what is read back.
      final finer = Owner(
        pid: 4242,
        started: DateTime.utc(2026, 10, 3, 7, 43, 34, 651, 987),
      );
      final local = Owner(pid: 4242, started: _started.toLocal());

      expect(finer, owner);
      expect(finer.hashCode, owner.hashCode);
      expect(local, owner);
      expect(local.hashCode, owner.hashCode);
      expect(jsonEncode(finer.toJson()), text);
      expect(jsonEncode(local.toJson()), text);
    });

    test('has a readable toString', () {
      expect(owner.toString(), 'Owner(pid: 4242, started: $_startedText)');
      expect(
        const Owner(pid: 4242, started: null).toString(),
        'Owner(pid: 4242, started: null)',
      );
    });

    group('fromJson', () {
      test('throws on a missing pid or started, naming the field', () {
        expect(
          _problem(() => Owner.fromJson(_decode('{"started":null}'))),
          'pid: missing',
        );
        // A model always has all its fields: no key is not null.
        expect(
          _problem(() => Owner.fromJson(_decode('{"pid":4242}'))),
          'started: missing',
        );
      });

      test('throws on a pid that is not an integer', () {
        for (final pid in ['"4242"', '4242.5', 'null', 'true', '[]']) {
          expect(
            _problem(() => Owner.fromJson(_decode('{"pid":$pid}'))),
            'pid: expected an integer',
            reason: pid,
          );
        }
      });

      test('throws on a started that is not a string or null', () {
        for (final started in ['1', 'true', '{}', '[]']) {
          expect(
            _problem(
              () => Owner.fromJson(_decode('{"pid":4242,"started":$started}')),
            ),
            'started: expected a string or null',
            reason: started,
          );
        }
      });

      test('throws on a started that is not written the way we write it', () {
        for (final started in [
          '', // nothing
          'garbage',
          '2026-10-03T07:43:34Z', // no milliseconds
          '2026-10-03T07:43:34.65Z', // too few digits
          '2026-10-03T07:43:34.651123Z', // more than three fractional digits
          '2026-10-03T07:43:34.651', // no zone
          '2026-10-03T09:43:34.651+02:00', // other zone
          '2026-02-30T07:43:34.651Z', // a date that does not exist
        ]) {
          expect(
            _problem(
              () =>
                  Owner.fromJson(_decode('{"pid":4242,"started":"$started"}')),
            ),
            'started: expected a UTC time like 2026-09-20T14:03:11.470Z',
            reason: started,
          );
        }
      });
    });
  });
}
