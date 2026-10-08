// Running a graph of nodes in a session (graph design §5–§8): branching,
// sets, joins and loops; nodes that are workflow functions or graphs; the
// journal, resume, the result, the places and the keys of its effects.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:nanoflow/nanoflow.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

final class Change {
  Change(this.path);

  factory Change.fromJson(Map<String, Object?> json) =>
      Change(json['path']! as String);

  final String path;

  Map<String, Object?> toJson() => {'path': path};
}

final class Report {
  Report(this.path, this.findings);

  factory Report.fromJson(Map<String, Object?> json) =>
      Report(json['path']! as String, json['findings']! as int);

  final String path;
  final int findings;

  Map<String, Object?> toJson() => {'path': path, 'findings': findings};
}

sealed class Collected {
  static Collected fromJson(Map<String, Object?> json) =>
      json['path'] == null ? Empty() : Found(Change.fromJson(json));

  Map<String, Object?> toJson();
}

final class Empty extends Exit<void> implements Collected {
  Empty() : super(null);

  @override
  Map<String, Object?> toJson() => {};
}

final class Found extends Exit<Change> implements Collected {
  Found(super.value);

  @override
  Map<String, Object?> toJson() => value.toJson();
}

sealed class Inspected {
  static Inspected fromJson(Map<String, Object?> json) {
    final report = Report.fromJson(json);
    return report.findings == 0 ? Clean(report) : Findings(report);
  }

  Map<String, Object?> toJson();
}

final class Clean extends Exit<Report> implements Inspected {
  Clean(super.value);

  @override
  Map<String, Object?> toJson() => value.toJson();
}

final class Findings extends Exit<Report> implements Inspected {
  Findings(super.value);

  @override
  Map<String, Object?> toJson() => value.toJson();
}

enum Verdict { pass, fail }

/// The nodes that ran, in order, with what they were given.
final calls = <String>[];

Future<Collected> collect(String branch) async {
  calls.add('collect $branch');
  return branch.isEmpty ? Empty() : Found(Change(branch));
}

Future<Inspected> inspect(Change change) async {
  calls.add('inspect ${change.path}');
  return change.path.endsWith('!')
      ? Clean(Report(change.path, 0))
      : Findings(Report(change.path, 1));
}

Future<Change> fix(Report report) async {
  calls.add('fix ${report.path}');
  return Change('${report.path}!');
}

Future<String> discard(void _) async {
  calls.add('discard');
  return 'discarded';
}

Future<String> publish(Report report) async {
  calls.add('publish ${report.path}');
  return 'published ${report.path}';
}

Future<int> notify(Report report) async {
  calls.add('notify ${report.path}');
  return report.findings;
}

Future<String> report((String, int) sent) async {
  calls.add('report');
  return '${sent.$1} with ${sent.$2} findings';
}

final review = Graph<String, String>('review', [
  Graph.start(collect).next({Empty: discard, Found: inspect}),
  Graph.part(inspect).next({
    Clean: {publish, notify},
    Findings: fix,
  }),
  Graph.part(fix).next(inspect),
  Graph.join([publish, notify]).next(report),
]);

Future<(Verdict, Report)> judge(Change change) async {
  calls.add('judge ${change.path}');
  return (
    change.path.length > 3 ? Verdict.pass : Verdict.fail,
    Report(change.path, 0),
  );
}

Future<String> accept(Report report) async => 'accepted ${report.path}';

Future<String> refuse(Report report) async => 'refused ${report.path}';

final judged = Graph<Change, String>('judged', [
  Graph.start(judge).next({Verdict.pass: accept, Verdict.fail: refuse}),
]);

final judgedOnlyPass = Graph<Change, (Verdict, Report)>('judgedOnlyPass', [
  Graph.start(judge).next({Verdict.pass: accept}),
]);

Future<Report?> lookup(String path) async =>
    path == 'none' ? null : Report(path, 2);

Future<String> ask(Object? nothing) async => 'asked for $nothing';

Future<String> use(Report? report) async => 'used ${report!.path}';

final looked = Graph<String, String>('looked', [
  Graph.start(lookup).next({null: ask}, otherwise: use),
]);

Future<bool> isLong(String text) async => text.length > 3;

Future<String> long(bool yes) async => 'long';

Future<String> short(bool yes) async => 'short';

final measured = Graph<String, String>('measured', [
  Graph.start(isLong).next({true: long, false: short}),
]);

final measuredOnlyLong = Graph<String, String>('measuredOnlyLong', [
  Graph.start(isLong).next({true: long}),
]);

Future<String> twoSteps(Flow f, String text) async {
  final first = await f.effect('first', () => '$text+1');
  return f.effect('second', () => '$first+2');
}

Future<String> shout(String text) async => text.toUpperCase();

final inner = Graph<String, String>('inner', [Graph.start(shout)]);

final outer = Graph<String, String>('outer', [
  Graph.start(twoSteps).next(inner),
]);

Future<String> callsGraph(Flow f, String text) async {
  final before = await f.effect('before', () => '$text<');
  return inner(f, before);
}

Future<int> tick(int n) async {
  calls.add('tick $n');
  return n + 1;
}

Future<int> tens(int n) async => n * 10;

Future<int> hundreds(int n) async => n * 100;

Future<int> sum((int, int) parts) async {
  calls.add('sum ${parts.$1} ${parts.$2}');
  return parts.$1 ~/ 10;
}

final ticking = Graph<int, int>('ticking', [
  Graph.start(tick).next({
    1: {tens, hundreds},
    2: {tens, hundreds},
  }),
  Graph.join([tens, hundreds]).next(sum),
  Graph.part(sum).next(tick),
]);

Future<int> joined((String, String) parts) async {
  calls.add('joined');
  return 0;
}

Future<bool> isOn(bool yes) async => yes;

Future<String> on(bool yes) async => 'on';

Future<String> off(bool yes) async => 'off';

final halfJoined = Graph<bool, Object?>('halfJoined', [
  Graph.start(isOn).next({true: on, false: off}),
  Graph.join([on, off]).next(joined),
]);

/// Opened when a [slow] node may finish.
var slowGate = Completer<void>();

Future<String> boom(String text) async => throw StateError('boom $text');

Future<String> slow(String text) async {
  await slowGate.future;
  return 'slow $text';
}

Future<String> both((String, String) parts) async => 'both';

final failing = Graph<String, Object?>('failing', [
  Graph.start(shout).next({boom, slow}),
  Graph.join([boom, slow]).next(both),
]);

/// Opened to let a [waits] node finish.
var gate = Completer<void>();

/// Completed when a [waits] node starts.
var atGate = Completer<void>();

Future<String> waits(Report report) async {
  calls.add('waits ${report.path}');
  if (!atGate.isCompleted) atGate.complete();
  await gate.future;
  return 'past ${report.path}';
}

final gated = Graph<String, String>('gated', [
  Graph.start(collect).next({Found: judgeFound}),
  Graph.part(judgeFound).next({Verdict.pass: waits}),
]);

Future<(Verdict, Report)> judgeFound(Change change) => judge(change);

Future<int> paceA(int n) async {
  await pause();
  return n + 1;
}

Future<int> paceB(int n) async {
  await pause();
  return n;
}

Future<int> paceC(int n) async {
  await pause();
  return n * 2;
}

Future<int> paceD((int, int) parts) async {
  await pause();
  return parts.$1;
}

final paced = Graph<int, int>('paced', [
  Graph.start(paceA).next({paceB, paceC}),
  Graph.join([paceB, paceC]).next(paceD),
  Graph.part(paceD).next({1: paceA, 2: paceA}),
]);

final placed = Graph<String, String>('placed', [Graph.start(shout)]);

/// A value with a toJson whose type has no codec.
final class Unregistered {
  Map<String, Object?> toJson() => {};
}

Future<Unregistered> makesUnregistered(String text) async => Unregistered();

final unregistered = Graph<String, Object?>('unregistered', [
  Graph.start(makesUnregistered),
]);

/// A flow in [dir] with the codecs of the values above.
Flow flowIn(String dir) => Flow(directory: dir)
  ..addCodec(Change.fromJson)
  ..addCodec(Report.fromJson)
  ..addCodec(Collected.fromJson)
  ..addCodec(Inspected.fromJson)
  ..addEnum(Verdict.values);

/// The effects of the only session of [dir], in the order they started.
Future<List<Effect>> effectsIn(String dir) async =>
    (await onlySession(dir)).effects();

void main() {
  setUp(calls.clear);

  group('branching', () {
    test('by the type of an Exit gives its target the payload, and a set '
        'and a join run as declared', () async {
      final dir = await tempDir();
      final result = await flowIn(dir).run(review.call, 'main');
      expect(result, 'published main! with 0 findings');
      expect(calls, [
        'collect main',
        'inspect main',
        'fix main',
        'inspect main!',
        'publish main!',
        'notify main!',
        'report',
      ]);
      final effects = await effectsIn(dir);
      expect(
        [for (final e in effects) e.name],
        ['collect', 'inspect', 'fix', 'inspect', 'publish', 'notify', 'report'],
      );
      final byName = {for (final e in effects) e.name: e};
      expect(effects[3].after, byName['fix']!.key);
      expect(byName['publish']!.after, effects[3].key);
      expect(byName['notify']!.after, effects[3].key);
      expect(byName['report']!.after, byName['publish']!.key);
      expect({for (final e in effects) e.key}, hasLength(7));
    });

    test('the other way of the same graph', () async {
      final dir = await tempDir();
      expect(await flowIn(dir).run(review.call, ''), 'discarded');
      expect(calls, ['collect ', 'discard']);
    });

    test('by the first field of a pair gives its target the second', () async {
      final dir = await tempDir();
      expect(
        await flowIn(dir).run(judged.call, Change('long')),
        'accepted long',
      );
      expect(await flowIn(dir).run(judged.call, Change('ab')), 'refused ab');
    });

    test('by null, and otherwise with the output as it is', () async {
      final dir = await tempDir();
      expect(await flowIn(dir).run(looked.call, 'none'), 'asked for null');
      expect(await flowIn(dir).run(looked.call, 'lib'), 'used lib');
    });

    test('by a bool', () async {
      final dir = await tempDir();
      expect(await flowIn(dir).run(measured.call, 'long text'), 'long');
      expect(await flowIn(dir).run(measured.call, 'ab'), 'short');
    });

    test(
      'an output no key matches ends its branch, and is the result',
      () async {
        final dir = await tempDir();
        final result = await flowIn(dir).run(judgedOnlyPass.call, Change('ab'));
        expect(result.$1, Verdict.fail);
        expect(result.$2.path, 'ab');
      },
    );

    test('a result that is not the graph\'s type is a TypeError', () async {
      final dir = await tempDir();
      await expectLater(
        flowIn(dir).run(measuredOnlyLong.call, 'ab'),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('joins', () {
    test('fire once for each full set, round a loop', () async {
      final dir = await tempDir();
      expect(await flowIn(dir).run(ticking.call, 0), 3);
      expect(calls, ['tick 0', 'sum 10 100', 'tick 1', 'sum 20 200', 'tick 2']);
    });

    test('that never fill up end their branch, and the graph ends', () async {
      final dir = await tempDir();
      expect(await flowIn(dir).run(halfJoined.call, true), isNull);
      expect(calls, isNot(contains('joined')));
    });
  });

  test('a node that throws fails the session once the other branch has '
      'ended, and its join does not hold it', () async {
    final dir = await tempDir();
    slowGate = Completer();
    final session = await flowIn(dir).start(failing.call, 'x');
    final failed = expectLater(
      session.result,
      throwsA(isA<StateError>().having((e) => e.message, 'message', 'boom X')),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    slowGate.complete();
    await failed;
    expect(eventNamesOf(dir, session.id), contains('effect-finished'));
    final effects = await effectsIn(dir);
    expect([for (final e in effects) e.name], ['shout', 'boom', 'slow']);
  });

  test('a node whose output has no codec fails as it runs, with a '
      'CodecException naming its type', () async {
    final dir = await tempDir();
    await expectLater(
      flowIn(dir).run(unregistered.call, 'x'),
      throwsA(
        isA<CodecException>()
            .having((e) => e.type, 'type', Object)
            .having((e) => e.reason, 'reason', contains('Unregistered')),
      ),
    );
    final handle = await onlySession(dir);
    expect([
      for (final event in await eventsOf(handle)) event.runtimeType,
    ], contains(EffectFailed));
  });

  group('nodes that are not functions of one parameter', () {
    test('a workflow function runs its own effects, and a graph its own '
        'nodes', () async {
      final dir = await tempDir();
      expect(await flowIn(dir).run(outer.call, 'x'), 'X+1+2');
      final effects = await effectsIn(dir);
      expect([for (final e in effects) e.name], ['first', 'second', 'shout']);
    });

    test('a workflow function calls a graph as a function', () async {
      final dir = await tempDir();
      expect(await flowIn(dir).run(callsGraph, 'x'), 'X<');
      final effects = await effectsIn(dir);
      expect([for (final e in effects) e.name], ['before', 'shout']);
      expect(effects[1].after, effects[0].key);
    });
  });

  test('a session of a graph is named after it, unfinished finds it, and '
      'resume takes the nodes that finished from the journal, decoded by the '
      'types their functions return', () async {
    final dir = await tempDir();
    gate = Completer();
    atGate = Completer();
    final flow = flowIn(dir);
    final first = await flow.start(gated.call, 'main');
    await atGate.future;
    expect(await flowIn(dir).unfinished(gated.call), [first.id]);
    flow.stop();
    gate.complete();
    await expectLater(first.result, throwsA(isA<FlowStoppedException>()));
    calls.clear();
    gate = Completer()..complete();
    final resumed = await flowIn(dir).resume(gated.call, first.id);
    expect(await resumed.result, 'past main');
    expect(calls, ['waits main']);
    final handle = await openSession(dir, first.id);
    expect(handle.session.workflow, 'gated');
  });

  group('the place of a node\'s effect', () {
    test('is the one the graph file gives the node', () async {
      final dir = await tempDir();
      final file = GraphFile(
        format: graphFileFormat,
        package: 'g',
        fingerprint: 'sha256:0',
        sources: const {},
        builds: const {},
        workflows: const ['lib/g.dart#placed'],
        functions: const {
          'lib/g.dart#placed': GraphFunction(
            id: 'lib/g.dart#placed',
            name: 'placed',
            place: 'lib/g.dart:3',
            body: GraphBody(
              nodes: [
                EffectNode(id: '1', place: 'lib/g.dart:3', name: 'shout'),
              ],
              edges: [],
            ),
          ),
        },
        warnings: const [],
      );
      await File(p.join(dir, graphFileName))
          .writeAsString(jsonEncode(file.toJson()));
      await flowIn(dir).run(placed.call, 'x');
      expect((await effectsIn(dir)).single.place, 'lib/g.dart:3');
    });

    test('is null without a graph file', () async {
      final dir = await tempDir();
      await flowIn(dir).run(placed.call, 'x');
      expect((await effectsIn(dir)).single.place, isNull);
    });
  });

  test('gives the same keys and the same after whatever the timing', () async {
    Future<Map<String, String?>> keysAt(int seed) async {
      random = Random(seed);
      final dir = await tempDir();
      expect(await flowIn(dir).run(paced.call, 0), 3);
      return {for (final e in await effectsIn(dir)) e.key: e.after};
    }

    final first = await keysAt(1);
    expect(first, hasLength(12));
    for (var seed = 2; seed < 12; seed++) {
      expect(await keysAt(seed), first, reason: 'seed $seed');
    }
  });
}
