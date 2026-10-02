// The less obvious ways workflow code runs steps.
import 'dart:async';

import 'package:step_keys/flow.dart';

import 'support.dart';

/// Copies inside copies: each package builds its platforms side by side.
Future<void> nestedCopies(Flow f) async {
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
Future<void> reviewLoop(Flow f) async {
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
Future<void> identicalResults(Flow f) async {
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
Future<void> awaitedLater(Flow f) async {
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
Future<void> caughtFailure(Flow f) async {
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
Future<String> visit(Flow f, String dir, int depth) async {
  final listed = await f.step('list', () => work('$dir:$depth'));
  if (depth == 0) return listed;
  final children = await Future.wait([
    for (final child in ['a', 'b']) visit(f, '$dir/$child', depth - 1),
  ]);
  return f.step('merge', () => work('$listed[${children.join(',')}]'));
}

Future<void> recursion(Flow f) async {
  note = await visit(f, 'root', 2);
}

/// Steps in the body of an `await for` over a stream.
Future<void> overStream(Flow f) async {
  final seen = <String>[];
  await for (final event in Stream.fromIterable(['a', 'b', 'c'])) {
    await pause();
    seen.add(await f.step('handle', () => work('handled $event')));
  }
  note = await f.step('summary', () => work(seen.join(', ')));
}

/// Copies started one by one, with an ordinary await between the starts.
Future<void> staggeredStart(Flow f) async {
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
Future<void> notAStepFirst(Flow f) async {
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

void main() {
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
}
