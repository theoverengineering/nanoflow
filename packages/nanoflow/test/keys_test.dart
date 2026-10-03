// Step keys (spec §4.3, decision D1): the ways workflow code runs steps,
// ported from prototypes/step_keys.
import 'dart:async';
import 'dart:math';

import 'package:test/test.dart';

import 'support.dart';

/// Copies side by side as an async closure called in place.
Future<void> inPlace(Keyed f) async {
  final results = await Future.wait([
    for (final pkg in ['core', 'tool'])
      () async {
        final up = await f.step('upload', () => work('$pkg:uploaded'));
        await pause();
        final ok = await f.step('verify', () => work('$up:verified'));
        await pause();
        return f.step('tag', () => work('$ok:tagged'));
      }(),
  ]);
  note = await f.step('announce', () => work(results.join(' + ')));
}

/// Copies side by side as a closure given to map.
Future<void> viaMap(Keyed f) async {
  final results = await Future.wait(
    ['core', 'tool'].map((pkg) async {
      final up = await f.step('upload', () => work('$pkg:uploaded'));
      await pause();
      final ok = await f.step('verify', () => work('$up:verified'));
      await pause();
      return f.step('tag', () => work('$ok:tagged'));
    }),
  );
  note = await f.step('announce', () => work(results.join(' + ')));
}

/// The same body one package after another.
Future<void> sequential(Keyed f) async {
  final results = <String>[];
  for (final pkg in ['core', 'tool']) {
    final up = await f.step('upload', () => work('$pkg:uploaded'));
    await pause();
    final ok = await f.step('verify', () => work('$up:verified'));
    await pause();
    results.add(await f.step('tag', () => work('$ok:tagged')));
  }
  note = await f.step('announce', () => work(results.join(' + ')));
}

Future<String> tagIt(Keyed f, String ok) async {
  await pause();
  return f.step('tag', () => work('$ok:tagged'));
}

Future<String> publish(Keyed f, String pkg) async {
  final up = await f.step('upload', () => work('$pkg:uploaded'));
  await pause();
  final ok = await f.step('verify', () => work('$up:verified'));
  // No await, as the unnecessary_await_in_return lint asks: the stack no
  // longer shows publish inside tagIt.
  return tagIt(f, ok);
}

/// Copies side by side as a function.
Future<void> viaFunction(Keyed f) async {
  final results = await Future.wait([
    for (final pkg in ['core', 'tool']) publish(f, pkg),
  ]);
  note = await f.step('announce', () => work(results.join(' + ')));
}

/// Single steps side by side, then one after the join.
Future<void> singleSteps(Keyed f) async {
  final results = await Future.wait([
    f.step('publish', () => work('published')),
    f.step('notify', () => work('notified')),
  ]);
  note = await f.step('announce', () => work(results.join(' + ')));
}

/// Copies inside copies: each package builds its platforms side by side.
Future<void> nestedCopies(Keyed f) async {
  final results = await Future.wait([
    for (final pkg in ['core', 'tool'])
      () async {
        final src = await f.step('fetch', () => work(pkg));
        final builds = await Future.wait([
          for (final os in ['mac', 'linux'])
            () async {
              await pause();
              return f.step('build', () => work('$src@$os'));
            }(),
        ]);
        return f.step('pack', () => work(builds.join('+')));
      }(),
  ]);
  note = await f.step('announce', () => work(results.join(' | ')));
}

/// The README review loop: inspect, fix, inspect again until clean.
Future<void> reviewLoop(Keyed f) async {
  var path = await f.step('collect', () => work('lib/parseConfigFile.dart'));
  final log = <String>[];
  while (true) {
    final findings = await f.step(
      'inspect',
      () => work(RegExp('[A-Z]').allMatches(path).length),
    );
    log.add('$path:$findings');
    if (findings == 0) break;
    final current = path;
    path = await f.step(
      'fix',
      () => work(current.replaceFirst(RegExp('[A-Z]'), '_')),
    );
  }
  note = await f.step('publish', () => work(log.join(' ')));
}

/// Copies whose steps return the very same object: true, null, a constant.
Future<void> identicalResults(Keyed f) async {
  final results = await Future.wait([
    for (final pkg in ['core', 'tool', 'cli'])
      () async {
        final ok = await f.step('check', () => work(true));
        await f.step('log', () => work(null));
        final kind = await f.step('kind', () => work('library'));
        await pause();
        return f.step('report', () => work('$pkg:$ok:$kind'));
      }(),
  ]);
  note = await f.step('announce', () => work(results.join(' | ')));
}

/// A step started, other things awaited, the step awaited later.
Future<void> awaitedLater(Keyed f) async {
  final results = await Future.wait([
    for (final pkg in ['core', 'tool'])
      () async {
        final pending = f.step('download', () => work('$pkg.tar'));
        await pause();
        final file = await pending;
        return f.step('unpack', () => work('$file/'));
      }(),
  ]);
  note = await f.step('announce', () => work(results.join(' | ')));
}

/// A step that throws in one copy; the copy catches it and goes on.
Future<void> caughtFailure(Keyed f) async {
  final results = await Future.wait([
    for (final pkg in ['core', 'tool'])
      () async {
        try {
          await f.step('deploy', () async {
            await pause();
            if (pkg == 'tool') throw StateError('no disk');
            return '$pkg:deployed';
          });
          return await f.step('verify', () => work('$pkg:verified'));
        } on StateError {
          return f.step('rollback', () => work('$pkg:rolled back'));
        }
      }(),
  ]);
  note = await f.step('announce', () => work(results.join(' | ')));
}

/// A function that calls itself, with steps on every level.
Future<String> visit(Keyed f, String dir, int depth) async {
  final listed = await f.step('list', () => work('$dir:$depth'));
  if (depth == 0) return listed;
  final children = await Future.wait([
    for (final child in ['a', 'b']) visit(f, '$dir/$child', depth - 1),
  ]);
  return f.step('merge', () => work('$listed[${children.join(',')}]'));
}

Future<void> recursion(Keyed f) async {
  note = await visit(f, 'root', 2);
}

/// Steps in the body of an `await for` over a stream.
Future<void> overStream(Keyed f) async {
  final seen = <String>[];
  await for (final event in Stream.fromIterable(['a', 'b', 'c'])) {
    await pause();
    seen.add(await f.step('handle', () => work('handled $event')));
  }
  note = await f.step('summary', () => work(seen.join(', ')));
}

/// Copies started one by one, with an ordinary await between the starts.
Future<void> staggeredStart(Keyed f) async {
  final copies = <Future<String>>[];
  for (final pkg in ['core', 'tool', 'cli']) {
    copies.add(() async {
      final up = await f.step('upload', () => work('$pkg:uploaded'));
      return f.step('verify', () => work('$up:verified'));
    }());
    await pause();
  }
  final results = await Future.wait(copies);
  note = await f.step('announce', () => work(results.join(' | ')));
}

/// Copies whose first await is not a step: an http call, say.
Future<void> notAStepFirst(Keyed f) async {
  final results = await Future.wait([
    for (final pkg in ['core', 'tool'])
      () async {
        await pause(); // like http.get outside any step
        final up = await f.step('upload', () => work('$pkg:uploaded'));
        return f.step('verify', () => work('$up:verified'));
      }(),
  ]);
  note = await f.step('announce', () => work(results.join(' | ')));
}

/// A step awaited later through Future.wait, then copies whose first await is
/// not a step: the step future is handed to Future.wait done or not yet.
Future<void> waitedLaterThenCopies(Keyed f) async {
  final pending = f.step('download', () => work('src.tar'));
  await pause();
  await pause();
  final [source] = await Future.wait([pending]);
  final results = await Future.wait([
    for (final pkg in ['core', 'tool'])
      () async {
        await pause(); // like http.get outside any step
        final up = await f.step('upload', () => work('$pkg:$source'));
        return f.step('verify', () => work('$up:verified'));
      }(),
  ]);
  note = await f.step('announce', () => work(results.join(' | ')));
}

void main() {
  checkWorkflow('copies as a closure called in place', inPlace);
  checkWorkflow('copies as a closure given to map', viaMap);
  checkWorkflow('one after another in a for', sequential);
  checkWorkflow('copies as a function returning without await', viaFunction);
  checkWorkflow('single steps side by side', singleSteps);
  checkWorkflow('copies inside copies', nestedCopies);
  checkWorkflow('the review loop', reviewLoop);
  checkWorkflow('copies whose steps return the same object', identicalResults);
  checkWorkflow('a step awaited later than started', awaitedLater);
  checkWorkflow('a failed step caught in a copy', caughtFailure);
  checkWorkflow('a function calling itself', recursion);
  checkWorkflow('steps in await for', overStream);
  checkWorkflow('copies started one by one', staggeredStart);
  checkWorkflow(
    'copies that begin with an await that is not a step',
    notAStepFirst,
  );
  checkWorkflow(
    'a step awaited later through Future.wait, then copies that begin with '
    'an await that is not a step',
    waitedLaterThenCopies,
  );

  test('keys a step after the join in the parent, not in a copy', () async {
    random = Random(1);
    final f = Keyed();
    await f.run(viaFunction);
    final announce = f.after.keys.singleWhere((k) => k.startsWith('announce'));
    // The parent took no step's result: a step in a copy would follow the
    // copy's tag.
    expect(f.after[announce], isNull);
    // And each copy's tag follows its own verify, which follows its own
    // upload: each value goes on from the one before it.
    final tags = f.after.keys.where((k) => k.startsWith('tag#')).toList();
    expect(tags, hasLength(2));
    final uploads = <String>{};
    for (final tag in tags) {
      final verify = f.after[tag]!;
      final upload = f.after[verify]!;
      expect(verify, startsWith('verify#'));
      expect(upload, startsWith('upload#'));
      expect(f.record[tag], startsWith('${f.record[verify]}'));
      expect(f.record[verify], startsWith('${f.record[upload]}'));
      uploads.add(upload);
    }
    expect(uploads, hasLength(2));
  });

  group('a key', () {
    final root = h('');

    test('is the name, the number among the steps of that name in the '
        'context and the hash of the context', () async {
      random = Random(1);
      final f = Keyed();
      await f.run((f) async {
        final collect = f.step('collect', () => work('a'));
        unawaited(f.step<String>('collect', () => work('b')));
        await collect;
        await f.step('inspect', () => work('c'));
      });
      expect(root, 'e3b0c44298fc1c14');
      expect(f.after, {
        'collect#1@$root': null,
        'collect#2@$root': null,
        // Resumed with collect's result, the call goes on in its context: the
        // collect step's key, and collect is the step before.
        'inspect#1@${h('collect#1@$root')}': 'collect#1@$root',
      });
    });

    test('of a step called in a step body has the body\'s own context, '
        'the step\'s ~0', () async {
      random = Random(1);
      final f = Keyed();
      await f.run((f) async {
        await f.step('outer', () => f.step('inner', () => work('x')));
      });
      expect(f.after, {
        'outer#1@$root': null,
        'inner#1@${h(h('outer#1@$root/~0'))}': 'outer#1@$root',
      });
    });
  });
}
