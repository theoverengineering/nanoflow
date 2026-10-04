import 'dart:async';
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart' show FsStore, SessionHandle;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

/// A value of the app's own: JSON through its `toJson` and `fromJson`.
final class Report {
  const Report(this.title, this.issues);

  factory Report.fromJson(Map<String, Object?> json) =>
      Report(json['title']! as String, json['issues']! as int);

  final String title;
  final int issues;

  Map<String, Object?> toJson() => {'title': title, 'issues': issues};

  @override
  bool operator ==(Object other) =>
      other is Report && other.title == title && other.issues == issues;

  @override
  int get hashCode => Object.hash(title, issues);

  @override
  String toString() => 'Report($title, $issues)';
}

/// The input of [keepsReports], a value of the app's own.
final class Change {
  const Change(this.branch);

  factory Change.fromJson(Map<String, Object?> json) =>
      Change(json['branch']! as String);

  final String branch;

  Map<String, Object?> toJson() => {'branch': branch};

  @override
  bool operator ==(Object other) => other is Change && other.branch == branch;

  @override
  int get hashCode => branch.hashCode;
}

/// A class with a `fromJson` but without a `toJson`.
final class Unwritable {
  const Unwritable();

  factory Unwritable.fromJson(Map<String, Object?> json) => const Unwritable();
}

/// A `fromJson` that gives no [Report]: the cast in it fails.
Report notAReport(Map<String, Object?> json) => json['title'] as Report;

/// A flow in [dir] without codecs.
Flow plain(String dir) => Flow(directory: dir);

/// A flow in [dir] with the codecs of [Report] and [Change].
Flow withCodecs(String dir) => Flow(directory: dir)
  ..addCodec(Report.fromJson)
  ..addCodec(Change.fromJson);

/// The names of the effect bodies that ran, in order.
final ran = <String>[];

/// What the workflow last run got: its input and what each effect gave it.
final got = <String, Object?>{};

/// The body of the effect [name], which gives [value].
T body<T>(String name, T value) {
  ran.add(name);
  return value;
}

/// Calls the effect [name], which gives [value] as a [T], and keeps what it
/// gave in [got].
Future<void> keep<T>(Flow f, String name, T value) async {
  got[name] = await f.effect<T>(name, () => body(name, value));
}

/// Opened to let a session past its effect `gate`.
var gate = Completer<void>();

/// Completed when a session reaches its effect `gate`.
var atGate = Completer<void>();

/// The effect `gate`, which waits until [gate] is opened.
Future<void> passGate(Flow f) => f.effect('gate', () {
  ran.add('gate');
  if (!atGate.isCompleted) atGate.complete();
  return gate.future;
});

/// Effects that give JSON values of many types, then a gate.
Future<List<String>> keepsJson(Flow f, List<String> branches) async {
  got['input'] = branches;
  await keep(f, 'names', ['a', 'b']);
  await keep(f, 'byDir', {
    'lib': ['a.dart'],
    'test': <String>[],
  });
  await keep(f, 'deep', [
    [1, 2],
    [3],
  ]);
  await keep(f, 'count', 2);
  await keep(f, 'whole', 2.0);
  await keep(f, 'flag', true);
  await keep<String?>(f, 'none', null);
  await keep<Object?>(f, 'any', {
    'a': [1, 'b'],
  });
  await passGate(f);
  return f.effect('result', () => body('result', [...branches, 'done']));
}

/// Effects that give values of [Report], and lists, maps and nullables of
/// them, then a gate.
Future<Report> keepsReports(Flow f, Change change) async {
  got['input'] = change;
  await keep(f, 'report', Report(change.branch, 2));
  await keep(f, 'reports', const [Report('a', 1), Report('b', 0)]);
  await keep(f, 'byName', const {'a': Report('a', 1)});
  await keep<Report?>(f, 'none', null);
  await keep<Report?>(f, 'some', const Report('s', 3));
  await keep<List<Report>?>(f, 'maybeAll', const [Report('m', 4)]);
  await passGate(f);
  return f.effect(
    'result',
    () => body('result', Report('${change.branch}: done', 0)),
  );
}

/// Runs a session of [workflow] with [input] on the flow [make] gives until
/// its effect `gate`, and stops the flow there; then resumes the session past
/// the gate on another flow [make] gives, the effects before the gate taken
/// from the journal.
Future<FlowSession<R>> resumedPastGate<I, R>(
  Flow Function() make,
  Future<R> Function(Flow f, I input) workflow,
  I input,
) async {
  gate = Completer();
  atGate = Completer();
  final flow = make();
  final first = await flow.start(workflow, input);
  await atGate.future;
  flow.stop();
  gate.complete();
  await expectLater(first.result, throwsA(isA<FlowStoppedException>()));
  ran.clear();
  got.clear();
  return make().resume(workflow, first.id);
}

/// Calls the effect `value`, which gives [value] as a [T]; gives the text of
/// the [CodecException] it throws.
Future<String> codecErrorOf<T>(Flow f, T value) async {
  try {
    await f.effect<T>('value', () => value);
  } on CodecException catch (e) {
    return '$e';
  }
  return 'no CodecException';
}

Future<String> unregistered(Flow f, String x) =>
    codecErrorOf(f, const Report('x', 1));

Future<String> unregisteredList(Flow f, String x) =>
    codecErrorOf(f, const [Report('x', 1)]);

Future<String> unwritable(Flow f, String x) =>
    codecErrorOf(f, const Unwritable());

Future<String> reportAsObject(Flow f, String x) =>
    codecErrorOf<Object?>(f, const Report('x', 1));

Future<String> listAsIterable(Flow f, String x) =>
    codecErrorOf<Iterable<String>>(f, ['x']);

/// The effect `report`, which gives a [Report], then a gate.
Future<Report> reportThenGate(Flow f, String x) async {
  await keep(f, 'report', const Report('x', 1));
  await passGate(f);
  return f.effect('result', () => body('result', const Report('x', 0)));
}

Future<String> describeChange(Flow f, Change change) async => change.branch;

Future<Report> reportResult(Flow f, String x) async => const Report('x', 0);

/// Calls the effect `report`, which gives a [Report]; gives the text of the
/// [CodecException] it throws.
Future<String> takesReport(Flow f, String x) async {
  try {
    await f.effect('report', () => body('report', const Report('x', 1)));
  } on CodecException catch (e) {
    return '$e';
  }
  return 'no CodecException';
}

/// Writes a session of [workflow] with the input [input] in [dir], as a
/// process that ended would have left it; [build] adds to it. Gives its id.
Future<String> writeSession(
  String dir,
  String workflow,
  Object? input, {
  Future<void> Function(SessionHandle handle)? build,
}) async {
  final handle = await FsStore(runsDirOf(dir)).createSession(
    workflow: workflow,
    graph: null,
    input: (value: input),
    code: null,
  );
  await build?.call(handle);
  await handle.release();
  return handle.session.id;
}

void main() {
  setUp(() {
    ran.clear();
    got.clear();
  });

  test('values of JSON types need no codec and come back from the journal '
      'with their types', () async {
    final dir = await tempDir();

    final session = await resumedPastGate(() => plain(dir), keepsJson, [
      'main',
      'dev',
    ]);

    expect(await session.result, isA<List<String>>());
    expect(await session.result, ['main', 'dev', 'done']);
    expect(ran, ['gate', 'result']);
    expect(got['input'], isA<List<String>>());
    expect(got['input'], ['main', 'dev']);
    expect(got['names'], isA<List<String>>());
    expect(got['names'], ['a', 'b']);
    expect(got['byDir'], isA<Map<String, List<String>>>());
    expect(got['byDir'], {
      'lib': ['a.dart'],
      'test': <String>[],
    });
    expect(got['deep'], isA<List<List<int>>>());
    expect(got['deep'], [
      [1, 2],
      [3],
    ]);
    expect(got['count'], 2);
    expect(got['whole'], isA<double>());
    expect(got['whole'], 2.0);
    expect(got['flag'], true);
    expect(got['none'], isNull);
    expect(got['any'], {
      'a': [1, 'b'],
    });
  });

  test('a value of a type with a codec comes back from the journal equal, '
      'and so do lists, maps and nullables of it; so do the input and the '
      'result', () async {
    final dir = await tempDir();

    final session = await resumedPastGate(
      () => withCodecs(dir),
      keepsReports,
      const Change('main'),
    );

    expect(await session.result, const Report('main: done', 0));
    expect(ran, ['gate', 'result']);
    expect(got['input'], const Change('main'));
    expect(got['report'], const Report('main', 2));
    expect(got['reports'], isA<List<Report>>());
    expect(got['reports'], const [Report('a', 1), Report('b', 0)]);
    expect(got['byName'], isA<Map<String, Report>>());
    expect(got['byName'], const {'a': Report('a', 1)});
    expect(got['none'], isNull);
    expect(got['some'], const Report('s', 3));
    expect(got['maybeAll'], isA<List<Report>>());
    expect(got['maybeAll'], const [Report('m', 4)]);

    // A session that has finished gives its saved result.
    final finished = await withCodecs(dir).resume(keepsReports, session.id);
    expect(await finished.result, const Report('main: done', 0));
    expect(ran, ['gate', 'result']);
  });

  group('an effect whose value does not come back from JSON fails with a '
      'CodecException that names its type, the first time it runs', () {
    for (final (title, workflow, flowOf, error) in [
      (
        'a type without a codec',
        unregistered,
        plain,
        'CodecException: Report: it is neither a JSON type nor made of types '
            'with a codec',
      ),
      (
        'a list of a type without a codec',
        unregisteredList,
        plain,
        'CodecException: List<Report>: it is neither a JSON type nor made of '
            'types with a codec',
      ),
      (
        'a type with a codec but without toJson',
        unwritable,
        (String dir) => plain(dir)..addCodec(Unwritable.fromJson),
        'CodecException: Unwritable: a Unwritable has no toJson',
      ),
      (
        'a codec whose fromJson does not give its type',
        unregistered,
        (String dir) => plain(dir)..addCodec(notAReport),
        'CodecException: Report: the JSON does not decode: ',
      ),
      (
        'a value of a type with a codec declared as Object?',
        reportAsObject,
        withCodecs,
        'CodecException: Object?: a Report is JSON only through its toJson',
      ),
      (
        'a list declared as an Iterable',
        listAsIterable,
        plain,
        'CodecException: Iterable<String>: it is neither a JSON type nor made '
            'of types with a codec',
      ),
    ]) {
      test(title, () async {
        final dir = await tempDir();
        final caught = await flowOf(dir).run(workflow, 'x');

        expect(caught, startsWith(error));
        final events = await eventsOf(await onlySession(dir));
        expect(events.map((e) => e.name), [
          'session-started',
          'effect-started',
          'effect-failed',
          'session-finished',
        ]);
        expect((events[2] as EffectFailed).error, caught);
      });
    }
  });

  test('an input of a type without a codec fails start, and no session is '
      'written', () async {
    final dir = await tempDir();

    await expectLater(
      Flow(directory: dir).start(describeChange, const Change('main')),
      throwsA(isA<CodecException>().having((e) => e.type, 'type', Change)),
    );
    expect(Directory(p.join(dir, 'runs')).existsSync(), isFalse);
  });

  test('a result of a type without a codec fails the session with a '
      'CodecException', () async {
    final dir = await tempDir();

    await expectLater(
      Flow(directory: dir).run(reportResult, 'x'),
      throwsA(isA<CodecException>().having((e) => e.type, 'type', Report)),
    );
    final events = await eventsOf(await onlySession(dir));
    expect(
      events.last,
      isA<SessionFailed>().having(
        (e) => e.error,
        'error',
        startsWith('CodecException: Report: '),
      ),
    );
  });

  group('a saved value that does not come back as its type is a '
      'CodecException', () {
    test('for the input: resume throws it, and writes nothing', () async {
      final dir = await tempDir();
      final id = await writeSession(dir, 'describeChange', {'branch': 1});
      final files = filesUnder(sessionDirOf(dir, id));

      await expectLater(
        withCodecs(dir).resume(describeChange, id),
        throwsA(isA<CodecException>().having((e) => e.type, 'type', Change)),
      );
      expect(filesUnder(sessionDirOf(dir, id)), files);
      expect(await ownerCheck(dir, id), 'opened');
    });

    test('for the result of a finished session: its result', () async {
      final dir = await tempDir();
      final id = await writeSession(
        dir,
        'reportResult',
        'x',
        build: (handle) async {
          final outputId = await handle.writeDocument(['not', 'a report']);
          await handle.appendEvent(
            SessionFinished(time: systemClock(), outputId: outputId),
          );
        },
      );

      final session = await withCodecs(dir).resume(reportResult, id);

      await expectLater(
        session.result,
        throwsA(isA<CodecException>().having((e) => e.type, 'type', Report)),
      );
    });
  });

  test('an effect whose saved result has a type without a codec now neither '
      'runs nor writes: the session ends with the CodecException, and resumes '
      'once the codec is registered', () async {
    final dir = await tempDir();
    gate = Completer();
    atGate = Completer();
    final flow = withCodecs(dir);
    final first = await flow.start(reportThenGate, 'x');
    await atGate.future;
    flow.stop();
    gate.complete();
    await expectLater(first.result, throwsA(isA<FlowStoppedException>()));
    expect(ran, ['report', 'gate']);
    ran.clear();
    final written = eventNamesOf(dir, first.id);

    final withoutCodec = await plain(dir).resume(reportThenGate, first.id);

    await expectLater(
      withoutCodec.result,
      throwsA(
        isA<CodecException>()
            .having((e) => e.type, 'type', Report)
            .having((e) => e.reason, 'reason', contains('addCodec')),
      ),
    );
    expect(ran, isEmpty);
    expect(eventNamesOf(dir, first.id), [...written, 'session-resumed']);
    expect(await ownerCheck(dir, first.id), 'opened');

    final resumed = await withCodecs(dir).resume(reportThenGate, first.id);

    expect(await resumed.result, const Report('x', 0));
    expect(ran, ['gate', 'result']);
    final state = replaySession(await eventsOf(await onlySession(dir)));
    expect(state.status, SessionStatus.finished);
    expect(
      [for (final effect in state.effects) effect.starts],
      [1, 2, 1],
      reason: 'report, gate and result',
    );
  });

  test('an effect whose saved result no longer comes back as its type runs '
      'again, in its record, and its new result is saved', () async {
    final dir = await tempDir();
    late Effect written;
    final id = await writeSession(
      dir,
      'takesReport',
      'x',
      build: (handle) async {
        written = await handle.createEffect(
          name: 'report',
          key: 'report#1@${h('')}',
          after: null,
          place: null,
        );
        await handle.appendEvent(
          EffectStarted(time: systemClock(), effectId: written.id),
        );
        final outputId = await handle.writeDocument('not a report');
        await handle.appendEvent(
          EffectFinished(
            time: systemClock(),
            effectId: written.id,
            outputId: outputId,
          ),
        );
        await handle.setEffectOutput(written, outputId);
      },
    );

    final session = await withCodecs(dir).resume(takesReport, id);

    expect(await session.result, 'no CodecException');
    expect(ran, ['report']);
    final handle = await openSession(dir, id);
    final events = await eventsOf(handle);
    expect(events.map((e) => e.name), [
      'session-started',
      'effect-started',
      'effect-finished',
      'session-resumed',
      'effect-started',
      'effect-finished',
      'session-finished',
    ]);
    final [effect] = replaySession(events).effects;
    expect(effect.effectId, written.id);
    expect(effect.starts, 2);
    final [record] = await handle.effects();
    expect(record.id, written.id);
    expect(record.outputId, effect.outputId);
    expect(await handle.documentValue(effect.outputId!), {
      'title': 'x',
      'issues': 1,
    });
  });
}
