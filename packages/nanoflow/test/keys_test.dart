// Effect keys (spec §4.3, decision D1): the ways workflow code runs effects,
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
        final up = await f.effect('upload', () => work('$pkg:uploaded'));
        await pause();
        final ok = await f.effect('verify', () => work('$up:verified'));
        await pause();
        return f.effect('tag', () => work('$ok:tagged'));
      }(),
  ]);
  note = await f.effect('announce', () => work(results.join(' + ')));
}

/// Copies side by side as a closure given to map.
Future<void> viaMap(Keyed f) async {
  final results = await Future.wait(
    ['core', 'tool'].map((pkg) async {
      final up = await f.effect('upload', () => work('$pkg:uploaded'));
      await pause();
      final ok = await f.effect('verify', () => work('$up:verified'));
      await pause();
      return f.effect('tag', () => work('$ok:tagged'));
    }),
  );
  note = await f.effect('announce', () => work(results.join(' + ')));
}

/// The same body one package after another.
Future<void> sequential(Keyed f) async {
  final results = <String>[];
  for (final pkg in ['core', 'tool']) {
    final up = await f.effect('upload', () => work('$pkg:uploaded'));
    await pause();
    final ok = await f.effect('verify', () => work('$up:verified'));
    await pause();
    results.add(await f.effect('tag', () => work('$ok:tagged')));
  }
  note = await f.effect('announce', () => work(results.join(' + ')));
}

Future<String> tagIt(Keyed f, String ok) async {
  await pause();
  return f.effect('tag', () => work('$ok:tagged'));
}

Future<String> publish(Keyed f, String pkg) async {
  final up = await f.effect('upload', () => work('$pkg:uploaded'));
  await pause();
  final ok = await f.effect('verify', () => work('$up:verified'));
  // No await, as the unnecessary_await_in_return lint asks: the stack no
  // longer shows publish inside tagIt.
  return tagIt(f, ok);
}

/// Copies side by side as a function.
Future<void> viaFunction(Keyed f) async {
  final results = await Future.wait([
    for (final pkg in ['core', 'tool']) publish(f, pkg),
  ]);
  note = await f.effect('announce', () => work(results.join(' + ')));
}

/// Single effects side by side, then one after the join.
Future<void> singleEffects(Keyed f) async {
  final results = await Future.wait([
    f.effect('publish', () => work('published')),
    f.effect('notify', () => work('notified')),
  ]);
  note = await f.effect('announce', () => work(results.join(' + ')));
}

/// Copies inside copies: each package builds its platforms side by side.
Future<void> nestedCopies(Keyed f) async {
  final results = await Future.wait([
    for (final pkg in ['core', 'tool'])
      () async {
        final src = await f.effect('fetch', () => work(pkg));
        final builds = await Future.wait([
          for (final os in ['mac', 'linux'])
            () async {
              await pause();
              return f.effect('build', () => work('$src@$os'));
            }(),
        ]);
        return f.effect('pack', () => work(builds.join('+')));
      }(),
  ]);
  note = await f.effect('announce', () => work(results.join(' | ')));
}

/// The README review loop: inspect, fix, inspect again until clean.
Future<void> reviewLoop(Keyed f) async {
  var path = await f.effect('collect', () => work('lib/parseConfigFile.dart'));
  final log = <String>[];
  while (true) {
    final findings = await f.effect(
      'inspect',
      () => work(RegExp('[A-Z]').allMatches(path).length),
    );
    log.add('$path:$findings');
    if (findings == 0) break;
    final current = path;
    path = await f.effect(
      'fix',
      () => work(current.replaceFirst(RegExp('[A-Z]'), '_')),
    );
  }
  note = await f.effect('publish', () => work(log.join(' ')));
}

/// Copies whose effects return the very same object: true, null, a constant.
Future<void> identicalResults(Keyed f) async {
  final results = await Future.wait([
    for (final pkg in ['core', 'tool', 'cli'])
      () async {
        final ok = await f.effect('check', () => work(true));
        await f.effect('log', () => work(null));
        final kind = await f.effect('kind', () => work('library'));
        await pause();
        return f.effect('report', () => work('$pkg:$ok:$kind'));
      }(),
  ]);
  note = await f.effect('announce', () => work(results.join(' | ')));
}

/// An effect started, other things awaited, the effect awaited later.
Future<void> awaitedLater(Keyed f) async {
  final results = await Future.wait([
    for (final pkg in ['core', 'tool'])
      () async {
        final pending = f.effect('download', () => work('$pkg.tar'));
        await pause();
        final file = await pending;
        return f.effect('unpack', () => work('$file/'));
      }(),
  ]);
  note = await f.effect('announce', () => work(results.join(' | ')));
}

/// An effect that throws in one copy; the copy catches it and goes on.
Future<void> caughtFailure(Keyed f) async {
  final results = await Future.wait([
    for (final pkg in ['core', 'tool'])
      () async {
        try {
          await f.effect('deploy', () async {
            await pause();
            if (pkg == 'tool') throw StateError('no disk');
            return '$pkg:deployed';
          });
          return await f.effect('verify', () => work('$pkg:verified'));
        } on StateError {
          return f.effect('rollback', () => work('$pkg:rolled back'));
        }
      }(),
  ]);
  note = await f.effect('announce', () => work(results.join(' | ')));
}

/// A function that calls itself, with effects on every level.
Future<String> visit(Keyed f, String dir, int depth) async {
  final listed = await f.effect('list', () => work('$dir:$depth'));
  if (depth == 0) return listed;
  final children = await Future.wait([
    for (final child in ['a', 'b']) visit(f, '$dir/$child', depth - 1),
  ]);
  return f.effect('merge', () => work('$listed[${children.join(',')}]'));
}

Future<void> recursion(Keyed f) async {
  note = await visit(f, 'root', 2);
}

/// Effects in the body of an `await for` over a stream.
Future<void> overStream(Keyed f) async {
  final seen = <String>[];
  await for (final event in Stream.fromIterable(['a', 'b', 'c'])) {
    await pause();
    seen.add(await f.effect('handle', () => work('handled $event')));
  }
  note = await f.effect('summary', () => work(seen.join(', ')));
}

/// Copies started one by one, with an ordinary await between the starts.
Future<void> staggeredStart(Keyed f) async {
  final copies = <Future<String>>[];
  for (final pkg in ['core', 'tool', 'cli']) {
    copies.add(() async {
      final up = await f.effect('upload', () => work('$pkg:uploaded'));
      return f.effect('verify', () => work('$up:verified'));
    }());
    await pause();
  }
  final results = await Future.wait(copies);
  note = await f.effect('announce', () => work(results.join(' | ')));
}

/// Copies whose first await is not an effect: an http call, say.
Future<void> notAnEffectFirst(Keyed f) async {
  final results = await Future.wait([
    for (final pkg in ['core', 'tool'])
      () async {
        await pause(); // like http.get outside any effect
        final up = await f.effect('upload', () => work('$pkg:uploaded'));
        return f.effect('verify', () => work('$up:verified'));
      }(),
  ]);
  note = await f.effect('announce', () => work(results.join(' | ')));
}

/// An effect awaited later through Future.wait, then copies whose first
/// await is not an effect: the effect future is handed to Future.wait done
/// or not yet.
Future<void> waitedLaterThenCopies(Keyed f) async {
  final pending = f.effect('download', () => work('src.tar'));
  await pause();
  await pause();
  final [source] = await Future.wait([pending]);
  final results = await Future.wait([
    for (final pkg in ['core', 'tool'])
      () async {
        await pause(); // like http.get outside any effect
        final up = await f.effect('upload', () => work('$pkg:$source'));
        return f.effect('verify', () => work('$up:verified'));
      }(),
  ]);
  note = await f.effect('announce', () => work(results.join(' | ')));
}

/// A plain future started early, like an http.get, awaited later — done by
/// then or not — then copies whose first await is not an effect.
Future<void> plainAwaitedLater(Keyed f) async {
  final pending = work('src.tar');
  await pause();
  await pause();
  final source = await pending;
  final results = await Future.wait([
    for (final pkg in ['core', 'tool'])
      () async {
        await pause(); // like http.get outside any effect
        final up = await f.effect('upload', () => work('$pkg:$source'));
        return f.effect('verify', () => work('$up:verified'));
      }(),
  ]);
  note = await f.effect('announce', () => work(results.join(' | ')));
}

/// Items of a stream that a producer adds after pauses, each handled in
/// `await for` by copies whose first await is not an effect: the stream
/// schedules its own microtasks only for items that wait.
Future<void> streamCopies(Keyed f) async {
  final controller = StreamController<String>();
  unawaited(() async {
    for (final item in ['a', 'b', 'c', 'd']) {
      await pause();
      await pause();
      controller.add(item);
    }
    await controller.close();
  }());
  final handled = <String>[];
  await for (final item in controller.stream) {
    final results = await Future.wait([
      for (final pkg in ['core', 'tool'])
        () async {
          await pause(); // like http.get outside any effect
          return f.effect('upload', () => work('$pkg:$item'));
        }(),
    ]);
    handled.add(results.join('+'));
  }
  note = await f.effect('announce', () => work(handled.join(' | ')));
}

Future<String> publishLater(Keyed f, String pkg) async {
  final up = await f.effect('upload', () => work('$pkg:uploaded'));
  return f.effect('verify', () => work('$up:verified'));
}

/// Copies that call a function with effects from a timer.
Future<void> fromTimers(Keyed f) async {
  final results = await Future.wait([
    for (final pkg in ['core', 'tool'])
      () async {
        await pause();
        return Future.delayed(
          Duration(milliseconds: random.nextInt(10)),
          () => publishLater(f, pkg),
        );
      }(),
  ]);
  note = await f.effect('announce', () => work(results.join(' | ')));
}

void main() {
  checkWorkflow('copies as a closure called in place', inPlace);
  checkWorkflow('copies as a closure given to map', viaMap);
  checkWorkflow('one after another in a for', sequential);
  checkWorkflow('copies as a function returning without await', viaFunction);
  checkWorkflow('single effects side by side', singleEffects);
  checkWorkflow('copies inside copies', nestedCopies);
  checkWorkflow('the review loop', reviewLoop);
  checkWorkflow(
    'copies whose effects return the same object',
    identicalResults,
  );
  checkWorkflow('an effect awaited later than started', awaitedLater);
  checkWorkflow('a failed effect caught in a copy', caughtFailure);
  checkWorkflow('a function calling itself', recursion);
  checkWorkflow('effects in await for', overStream);
  checkWorkflow('copies started one by one', staggeredStart);
  checkWorkflow(
    'copies that begin with an await that is not an effect',
    notAnEffectFirst,
  );
  checkWorkflow(
    'an effect awaited later through Future.wait, then copies that begin with '
    'an await that is not an effect',
    waitedLaterThenCopies,
  );
  checkWorkflow(
    'a plain future awaited later, then copies that begin with an await '
    'that is not an effect',
    plainAwaitedLater,
  );
  checkWorkflow(
    'items of a stream fed after pauses, each handled by copies',
    streamCopies,
  );
  checkWorkflow(
    'copies that call a function with effects from a timer',
    fromTimers,
  );

  test('keys an effect after the join in the parent, not in a copy', () async {
    random = Random(1);
    final f = Keyed();
    await f.run(viaFunction);
    final announce = f.after.keys.singleWhere((k) => k.startsWith('announce'));
    // The parent took no effect's result: an effect in a copy would follow the
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

    test('is the name, the number among the effects of that name in the '
        'context and the hash of the context', () async {
      random = Random(1);
      final f = Keyed();
      await f.run((f) async {
        final collect = f.effect('collect', () => work('a'));
        unawaited(f.effect<String>('collect', () => work('b')));
        await collect;
        await f.effect('inspect', () => work('c'));
      });
      expect(root, 'e3b0c44298fc1c14');
      expect(f.after, {
        'collect#1@$root': null,
        'collect#2@$root': null,
        // Resumed with collect's result, the call goes on in its context: the
        // collect effect's key, and collect is the effect before.
        'inspect#1@${h('collect#1@$root')}': 'collect#1@$root',
      });
    });

    test('of an effect called in an effect body has the body\'s own context, '
        'the effect\'s ~0', () async {
      random = Random(1);
      final f = Keyed();
      await f.run((f) async {
        await f.effect('outer', () => f.effect('inner', () => work('x')));
      });
      expect(f.after, {
        'outer#1@$root': null,
        'inner#1@${h(h('outer#1@$root/~0'))}': 'outer#1@$root',
      });
    });
  });
}
