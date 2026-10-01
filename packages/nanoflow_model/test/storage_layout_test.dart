import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:test/test.dart';

// Identifiers from the README's example `runs` tree.
const _sessionId = '3f9c2a7e-5b1d-4c8e-9a6f-0d2e4b7c1a35';
const _documentId = '8e1f4b2a-6c3d-4f7e-b5a9-2d0c7e6f1b48';
const _runId = '7d2b9e4f-1a6c-4b3e-8f5d-6c0a2e9b4d17';
const _stepId = '5a8c1e3f-7b2d-4e9a-a6c4-1f3d8b0e2c59';
const _isEmptyStepId = '0b6d2f9a-4e8c-4a1b-9d7e-3c5f6a2b8e04';
const _splitRunId = 'e2c5a8f1-9d4b-4f6e-b3a7-8c1e0d5f2a96';

void main() {
  group('names', () {
    test('are the ones the README lists', () {
      expect(runsDirName, 'runs');
      expect(sessionFileName, 'session.json');
      expect(documentsDirName, 'documents');
      expect(runFileName, 'run.json');
      expect(eventsFileName, 'log.jsonl');
      expect(stepsDirName, 'steps');
      expect(stepFileName, 'step.json');
      expect(logFileName, 'command.log');
    });
  });

  group('sessionDirName', () {
    test('is <graph>-<time to the second>-<id>', () {
      expect(
        sessionDirName(
          'review',
          DateTime.utc(2026, 9, 20, 14, 3, 11),
          _sessionId,
        ),
        'review-2026-09-20T14-03-11-$_sessionId',
      );
      expect(
        sessionDirName(
          'workflow',
          DateTime.utc(2026, 9, 20, 14, 3, 11),
          _sessionId,
        ),
        'workflow-2026-09-20T14-03-11-$_sessionId',
      );
    });

    test('drops the fraction of a second', () {
      expect(
        sessionDirName(
          'review',
          DateTime.utc(2026, 9, 20, 14, 3, 11, 999, 999),
          _sessionId,
        ),
        'review-2026-09-20T14-03-11-$_sessionId',
      );
    });

    test('uses the UTC time of a non-UTC DateTime', () {
      final local = DateTime.utc(2026, 9, 20, 14, 3, 11).toLocal();

      expect(
        sessionDirName('review', local, _sessionId),
        'review-2026-09-20T14-03-11-$_sessionId',
      );
    });
  });

  group('runDirName', () {
    test('is <time to the millisecond>-<id>', () {
      expect(
        runDirName(DateTime.utc(2026, 9, 20, 14, 3, 11, 470), _runId),
        '2026-09-20T14-03-11-470-$_runId',
      );
      expect(
        runDirName(DateTime.utc(2026, 9, 20, 14, 9, 52, 310), _splitRunId),
        '2026-09-20T14-09-52-310-$_splitRunId',
      );
    });

    test('pads the milliseconds to three digits', () {
      expect(
        runDirName(DateTime.utc(2026, 9, 20, 14, 3, 11), _runId),
        '2026-09-20T14-03-11-000-$_runId',
      );
      expect(
        runDirName(DateTime.utc(2026, 9, 20, 14, 3, 11, 7), _runId),
        '2026-09-20T14-03-11-007-$_runId',
      );
    });

    test('truncates microseconds', () {
      expect(
        runDirName(DateTime.utc(2026, 9, 20, 14, 3, 11, 470, 999), _runId),
        '2026-09-20T14-03-11-470-$_runId',
      );
    });

    test('uses the UTC time of a non-UTC DateTime', () {
      final local = DateTime.utc(2026, 9, 20, 14, 3, 11, 470).toLocal();

      expect(runDirName(local, _runId), '2026-09-20T14-03-11-470-$_runId');
    });

    test('sorts in creation order', () {
      final names = [
        runDirName(DateTime.utc(2026, 9, 20, 14, 9, 52, 310), _splitRunId),
        runDirName(DateTime.utc(2026, 9, 20, 14, 3, 11, 470), _runId),
        runDirName(DateTime.utc(2026, 9, 20, 14, 3, 11, 95), _splitRunId),
      ]..sort();

      expect(names, [
        '2026-09-20T14-03-11-095-$_splitRunId',
        '2026-09-20T14-03-11-470-$_runId',
        '2026-09-20T14-09-52-310-$_splitRunId',
      ]);
    });
  });

  group('stepDirName', () {
    test('is <time to the millisecond>-<node>-<id>', () {
      expect(
        stepDirName(
          DateTime.utc(2026, 9, 20, 14, 3, 11, 482),
          'collect',
          _stepId,
        ),
        '2026-09-20T14-03-11-482-collect-$_stepId',
      );
      expect(
        stepDirName(
          DateTime.utc(2026, 9, 20, 14, 5, 40, 117),
          'is-empty',
          _isEmptyStepId,
        ),
        '2026-09-20T14-05-40-117-is-empty-$_isEmptyStepId',
      );
    });

    test('keeps letters, digits, dots, underscores and dashes in the node', () {
      expect(
        stepDirName(
          DateTime.utc(2026, 9, 20, 14, 3, 11, 482),
          'Step_1.v2-b',
          _stepId,
        ),
        '2026-09-20T14-03-11-482-Step_1.v2-b-$_stepId',
      );
    });

    test('replaces every other character of the node with _', () {
      final startedAt = DateTime.utc(2026, 9, 20, 14, 3, 11, 482);

      expect(
        stepDirName(startedAt, 'collect data/v2', _stepId),
        '2026-09-20T14-03-11-482-collect_data_v2-$_stepId',
      );
      expect(
        stepDirName(startedAt, r'a\b:c*d', _stepId),
        '2026-09-20T14-03-11-482-a_b_c_d-$_stepId',
      );
      expect(
        stepDirName(startedAt, 'проверка', _stepId),
        '2026-09-20T14-03-11-482-________-$_stepId',
      );
    });

    test('replaces a character outside the BMP with one _', () {
      expect(
        stepDirName(DateTime.utc(2026, 9, 20, 14, 3, 11, 482), 'go🚀', _stepId),
        '2026-09-20T14-03-11-482-go_-$_stepId',
      );
    });

    test('uses the UTC time of a non-UTC DateTime', () {
      final local = DateTime.utc(2026, 9, 20, 14, 3, 11, 482).toLocal();

      expect(
        stepDirName(local, 'collect', _stepId),
        '2026-09-20T14-03-11-482-collect-$_stepId',
      );
    });
  });

  group('documentFileName', () {
    test('is <id>.json', () {
      expect(documentFileName(_documentId), '$_documentId.json');
    });
  });

  group('idOfDirName', () {
    test('finds the id of a session directory', () {
      expect(idOfDirName('review-2026-09-20T14-03-11-$_sessionId'), _sessionId);
    });

    test('finds the id of a run directory', () {
      expect(idOfDirName('2026-09-20T14-03-11-470-$_runId'), _runId);
    });

    test('finds the id of a step directory', () {
      expect(idOfDirName('2026-09-20T14-03-11-482-collect-$_stepId'), _stepId);
      expect(
        idOfDirName('2026-09-20T14-05-40-117-is-empty-$_isEmptyStepId'),
        _isEmptyStepId,
      );
    });

    test('finds the id in names the layout functions built', () {
      final startedAt = DateTime.utc(2026, 9, 20, 14, 3, 11, 482);
      final id = newId();

      expect(idOfDirName(sessionDirName('review', startedAt, id)), id);
      expect(idOfDirName(runDirName(startedAt, id)), id);
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
        '2026-09-20T14-03-11-470',
      ]) {
        expect(idOfDirName(name), isNull, reason: name);
      }
    });

    test('returns null when the last 36 characters are not an id', () {
      for (final name in [
        'review-2026-09-20T14-03-11-3f9c2a7e-5b1d-4c8e-9a6f-0d2e4b7c1a3', // 35
        'review-2026-09-20T14-03-11-3F9C2A7E-5B1D-4C8E-9A6F-0D2E4B7C1A35',
        'review-2026-09-20T14-03-11-3f9c2a7e-5b1d-4c8e-9a6f-0d2e4b7c1a35x',
        'review-2026-09-20T14-03-11-3f9c2a7e-5b1d-4c8e-9a6f-0d2e4b7c1a3g',
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

  group('isSessionDirOf', () {
    final dir = 'review-2026-09-20T14-03-11-$_sessionId';

    test('is true for <graph>-YYYY-MM-DDTHH-MM-SS-<id>', () {
      expect(isSessionDirOf(dir, 'review'), isTrue);
      expect(
        isSessionDirOf('workflow-2026-09-20T14-03-11-$_sessionId', 'workflow'),
        isTrue,
      );
    });

    test('is true for a directory sessionDirName built', () {
      final id = newId();
      final name = sessionDirName(
        'review',
        DateTime.utc(2026, 9, 20, 14, 3, 11),
        id,
      );

      expect(isSessionDirOf(name, 'review'), isTrue);
    });

    test('is false for the sessions of another graph', () {
      expect(isSessionDirOf(dir, 'workflow'), isFalse);
      expect(isSessionDirOf(dir, 'Review'), isFalse);
      expect(isSessionDirOf(dir, 'rev'), isFalse);
    });

    test('tells a graph from a graph whose name extends it with a dash', () {
      final other = 'review-x-2026-09-20T14-03-11-$_sessionId';

      expect(isSessionDirOf(other, 'review'), isFalse);
      expect(isSessionDirOf(other, 'review-x'), isTrue);
      expect(isSessionDirOf(dir, 'review-x'), isFalse);
    });

    test('takes the graph name literally, not as a pattern', () {
      expect(
        isSessionDirOf('axb-2026-09-20T14-03-11-$_sessionId', 'a.b'),
        isFalse,
      );
      expect(
        isSessionDirOf('a.b-2026-09-20T14-03-11-$_sessionId', 'a.b'),
        isTrue,
      );
      expect(
        isSessionDirOf('(a|b)-2026-09-20T14-03-11-$_sessionId', '(a|b)'),
        isTrue,
      );
    });

    test('is false for anything but the exact form', () {
      for (final name in [
        '',
        'review',
        'review-',
        '2026-09-20T14-03-11-$_sessionId', // no graph
        'review-$_sessionId', // no time
        'review-2026-09-20T14-03-11-470-$_sessionId', // time to the millisecond
        'review-2026-09-20T14:03:11-$_sessionId', // colons
        'review-2026-09-20T14-03-11-${_sessionId.toUpperCase()}',
        'review-2026-09-20T14-03-11-${_sessionId}x',
        'review-2026-09-20T14-03-11-$_sessionId.bak',
        'review-2026-09-20T14-03-11-3f9c2a7e-5b1d-4c8e-9a6f-0d2e4b7c1a3',
        ' review-2026-09-20T14-03-11-$_sessionId',
        'review-2026-09-20T14-03-11-$_sessionId\n',
        '.tmp-$_sessionId', // a session being built
        '2026-09-20T14-03-11-470-$_runId', // a run directory
        '2026-09-20T14-03-11-482-collect-$_stepId', // a step directory
      ]) {
        expect(isSessionDirOf(name, 'review'), isFalse, reason: name);
      }
    });
  });

  group('graphNameOf', () {
    test('is the file name without its extension', () {
      expect(graphNameOf('/a/review.yaml'), 'review');
      expect(graphNameOf('/a/graph.dart'), 'graph');
    });

    test('works for relative paths and files without a directory', () {
      expect(graphNameOf('examples/review/review.yaml'), 'review');
      expect(graphNameOf('review.yaml'), 'review');
    });

    test('drops only the last extension and ignores dots in directories', () {
      expect(graphNameOf('/a/review.test.yaml'), 'review.test');
      expect(graphNameOf('/a.b/review.yaml'), 'review');
    });

    test('keeps the name of a file without an extension', () {
      expect(graphNameOf('/a/review'), 'review');
    });
  });

  group('runsDirOf', () {
    test('is runs next to the graph file', () {
      expect(runsDirOf('/a/review.yaml'), '/a/runs');
      expect(runsDirOf('/a/b/graph.dart'), '/a/b/runs');
    });

    test('works for relative paths', () {
      expect(runsDirOf('examples/review/review.yaml'), 'examples/review/runs');
      expect(runsDirOf('review.yaml'), './runs');
    });

    test('works for a graph file in the root directory', () {
      expect(runsDirOf('/review.yaml'), '/runs');
    });
  });
}
