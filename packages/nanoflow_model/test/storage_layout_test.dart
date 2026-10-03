import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:test/test.dart';

// Identifiers for the spec's example `runs` tree.
const _sessionId = '3f9c2a7e-5b1d-4c8e-9a6f-0d2e4b7c1a35';
const _documentId = '8e1f4b2a-6c3d-4f7e-b5a9-2d0c7e6f1b48';
const _stepId = '5a8c1e3f-7b2d-4e9a-a6c4-1f3d8b0e2c59';
const _otherStepId = '0b6d2f9a-4e8c-4a1b-9d7e-3c5f6a2b8e04';

void main() {
  group('names', () {
    test('are the ones the spec lists', () {
      expect(runsDirName, 'runs');
      expect(sessionFileName, 'session.json');
      expect(documentsDirName, 'documents');
      expect(eventsFileName, 'log.jsonl');
      expect(stepsDirName, 'steps');
      expect(stepFileName, 'step.json');
      expect(logFileName, 'step.log');
      expect(ownerLockFileName, '.owner.lock');
    });
  });

  group('ownerLockOffset', () {
    test('is the byte 2^30 of the owner lock file', () {
      expect(ownerLockOffset, 1 << 30);
      expect(ownerLockOffset, 1073741824);
    });
  });

  group('sessionDirName', () {
    test('is <workflow>-<time to the second>-<id>', () {
      expect(
        sessionDirName('review', DateTime.utc(2026, 10, 3, 10), _sessionId),
        'review-2026-10-03T10-00-00-$_sessionId',
      );
      expect(
        sessionDirName(
          'publishAll',
          DateTime.utc(2026, 10, 3, 14, 3, 11),
          _sessionId,
        ),
        'publishAll-2026-10-03T14-03-11-$_sessionId',
      );
    });

    test('drops the fraction of a second', () {
      expect(
        sessionDirName(
          'review',
          DateTime.utc(2026, 10, 3, 10, 0, 0, 999, 999),
          _sessionId,
        ),
        'review-2026-10-03T10-00-00-$_sessionId',
      );
    });

    test('uses the UTC time of a non-UTC DateTime', () {
      final local = DateTime.utc(2026, 10, 3, 10).toLocal();

      expect(
        sessionDirName('review', local, _sessionId),
        'review-2026-10-03T10-00-00-$_sessionId',
      );
    });

    test('replaces every character of the workflow outside '
        '[A-Za-z0-9._-] with _', () {
      expect(
        sessionDirName(r'review$1', DateTime.utc(2026, 10, 3, 10), _sessionId),
        'review_1-2026-10-03T10-00-00-$_sessionId',
      );
      expect(
        sessionDirName('a/b c', DateTime.utc(2026, 10, 3, 10), _sessionId),
        'a_b_c-2026-10-03T10-00-00-$_sessionId',
      );
    });
  });

  group('stepDirName', () {
    test('is <time to the millisecond>-<name>-<id>', () {
      expect(
        stepDirName(
          DateTime.utc(2026, 10, 3, 10, 0, 0, 482),
          'collect',
          _stepId,
        ),
        '2026-10-03T10-00-00-482-collect-$_stepId',
      );
      expect(
        stepDirName(
          DateTime.utc(2026, 10, 3, 10, 5, 40, 117),
          'is-empty',
          _otherStepId,
        ),
        '2026-10-03T10-05-40-117-is-empty-$_otherStepId',
      );
    });

    test('pads the milliseconds to three digits and drops microseconds', () {
      expect(
        stepDirName(DateTime.utc(2026, 10, 3, 10), 'collect', _stepId),
        '2026-10-03T10-00-00-000-collect-$_stepId',
      );
      expect(
        stepDirName(
          DateTime.utc(2026, 10, 3, 10, 0, 0, 7, 999),
          'collect',
          _stepId,
        ),
        '2026-10-03T10-00-00-007-collect-$_stepId',
      );
    });

    test('keeps letters, digits, dots, underscores and dashes in the name', () {
      expect(
        stepDirName(
          DateTime.utc(2026, 10, 3, 10, 0, 0, 482),
          'Step_1.v2-b',
          _stepId,
        ),
        '2026-10-03T10-00-00-482-Step_1.v2-b-$_stepId',
      );
    });

    test('replaces every other character of the name with _', () {
      final startedAt = DateTime.utc(2026, 10, 3, 10, 0, 0, 482);

      expect(
        stepDirName(startedAt, 'collect data/v2', _stepId),
        '2026-10-03T10-00-00-482-collect_data_v2-$_stepId',
      );
      expect(
        stepDirName(startedAt, r'a\b:c*d', _stepId),
        '2026-10-03T10-00-00-482-a_b_c_d-$_stepId',
      );
      expect(
        stepDirName(startedAt, 'проверка', _stepId),
        '2026-10-03T10-00-00-482-________-$_stepId',
      );
    });

    test('replaces a character outside the BMP with one _', () {
      expect(
        stepDirName(DateTime.utc(2026, 10, 3, 10, 0, 0, 482), 'go🚀', _stepId),
        '2026-10-03T10-00-00-482-go_-$_stepId',
      );
    });

    test('uses the UTC time of a non-UTC DateTime', () {
      final local = DateTime.utc(2026, 10, 3, 10, 0, 0, 482).toLocal();

      expect(
        stepDirName(local, 'collect', _stepId),
        '2026-10-03T10-00-00-482-collect-$_stepId',
      );
    });

    test('sorts in creation order', () {
      final names = [
        stepDirName(DateTime.utc(2026, 10, 3, 10, 9, 52, 310), 'b', _stepId),
        stepDirName(DateTime.utc(2026, 10, 3, 10, 0, 0, 470), 'z', _stepId),
        stepDirName(DateTime.utc(2026, 10, 3, 10, 0, 0, 95), 'c', _stepId),
      ]..sort();

      expect(names, [
        '2026-10-03T10-00-00-095-c-$_stepId',
        '2026-10-03T10-00-00-470-z-$_stepId',
        '2026-10-03T10-09-52-310-b-$_stepId',
      ]);
    });
  });

  group('documentFileName', () {
    test('is <id>.json', () {
      expect(documentFileName(_documentId), '$_documentId.json');
    });
  });

  group('idOfDirName', () {
    test('finds the id of a session directory', () {
      expect(idOfDirName('review-2026-10-03T10-00-00-$_sessionId'), _sessionId);
    });

    test('finds the id of a step directory', () {
      expect(idOfDirName('2026-10-03T10-00-00-482-collect-$_stepId'), _stepId);
      expect(
        idOfDirName('2026-10-03T10-05-40-117-is-empty-$_otherStepId'),
        _otherStepId,
      );
    });

    test('finds the id in names the layout functions built', () {
      final startedAt = DateTime.utc(2026, 10, 3, 10, 0, 0, 482);
      final id = newId();

      expect(idOfDirName(sessionDirName('review', startedAt, id)), id);
      expect(idOfDirName(stepDirName(startedAt, 'a b', id)), id);
    });

    test('returns null for names without an id', () {
      for (final name in [
        '',
        'runs',
        'steps',
        'documents',
        'session.json',
        'review',
        '2026-10-03T10-00-00-482',
      ]) {
        expect(idOfDirName(name), isNull, reason: name);
      }
    });

    test('returns null when the last 36 characters are not an id', () {
      for (final name in [
        'review-2026-10-03T10-00-00-3f9c2a7e-5b1d-4c8e-9a6f-0d2e4b7c1a3', // 35
        'review-2026-10-03T10-00-00-3F9C2A7E-5B1D-4C8E-9A6F-0D2E4B7C1A35',
        'review-2026-10-03T10-00-00-3f9c2a7e-5b1d-4c8e-9a6f-0d2e4b7c1a35x',
        'review-2026-10-03T10-00-00-3f9c2a7e-5b1d-4c8e-9a6f-0d2e4b7c1a3g',
        '$_documentId.json',
      ]) {
        expect(idOfDirName(name), isNull, reason: name);
      }
    });

    test('returns null when the id is not preceded by a dash', () {
      expect(idOfDirName(_sessionId), isNull);
      expect(idOfDirName('review_$_sessionId'), isNull);
      expect(idOfDirName('review$_sessionId'), isNull);
    });
  });

  group('isSessionDirName', () {
    test('is true for <workflow>-YYYY-MM-DDTHH-MM-SS-<id>', () {
      expect(
        isSessionDirName('review-2026-10-03T10-00-00-$_sessionId'),
        isTrue,
      );
      expect(
        isSessionDirName('review-x-2026-10-03T10-00-00-$_sessionId'),
        isTrue,
      );
      expect(isSessionDirName('a-2026-10-03T10-00-00-$_sessionId'), isTrue);
    });

    test('is true for a directory sessionDirName built', () {
      final name = sessionDirName(
        r'any$workflow',
        DateTime.utc(2026, 10, 3, 10),
        newId(),
      );

      expect(isSessionDirName(name), isTrue);
    });

    test('is false for anything but the exact form', () {
      for (final name in [
        '',
        'review',
        'review-',
        '-2026-10-03T10-00-00-$_sessionId', // no workflow
        '2026-10-03T10-00-00-$_sessionId', // no workflow
        'review-$_sessionId', // no time
        'review-2026-10-03T10-00-00-470-$_sessionId', // to the millisecond
        'review-2026-10-03T10:00:00-$_sessionId', // colons
        'review-2026-10-03T10-00-00-${_sessionId.toUpperCase()}',
        'review-2026-10-03T10-00-00-${_sessionId}x',
        'review-2026-10-03T10-00-00-$_sessionId.bak',
        'review-2026-10-03T10-00-00-3f9c2a7e-5b1d-4c8e-9a6f-0d2e4b7c1a3',
        'review-2026-10-03T10-00-00-$_sessionId\n',
        're\nview-2026-10-03T10-00-00-$_sessionId',
        '.tmp-$_sessionId', // a session being built
        '2026-10-03T10-00-00-482-collect-$_stepId', // a step directory
        '$_documentId.json',
      ]) {
        expect(isSessionDirName(name), isFalse, reason: name);
      }
    });
  });

  group('runsDirOf', () {
    test('is runs in the project directory', () {
      expect(runsDirOf('/a/review'), '/a/review/runs');
      expect(runsDirOf('/'), '/runs');
    });

    test('works for relative paths', () {
      expect(runsDirOf('examples/review'), 'examples/review/runs');
      expect(runsDirOf('.'), './runs');
    });
  });
}
