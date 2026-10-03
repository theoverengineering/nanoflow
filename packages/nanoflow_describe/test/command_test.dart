import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_describe/nanoflow_describe.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Copies everything in the directory [from] into [to].
Future<void> copyDir(String from, String to) async {
  await for (final entity in Directory(from).list(recursive: true)) {
    if (entity is! File) continue;
    final target = File(p.join(to, p.relative(entity.path, from: from)));
    await target.parent.create(recursive: true);
    await entity.copy(target.path);
  }
}

/// Waits until [done] holds, looking every 50 ms for up to [seconds].
Future<void> until(
  String what,
  bool Function() done, {
  int seconds = 10,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('waited $seconds s for $what');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  // The review fixture as a package of its own. It is inside the workspace,
  // so that the analyzer finds `package:nanoflow`, in a directory whose name
  // starts with `.`, which `dart analyze` and `dart format` of the workspace
  // pass by.
  late String dir;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() async {
    final temp = await Directory(p.join('test', 'fixtures'))
        .createTemp('.tmp-');
    dir = p.normalize(temp.absolute.path);
    await copyDir(p.join('test', 'fixtures', 'review'), dir);
    await File(p.join(dir, 'pubspec.yaml')).writeAsString('name: review\n');
    out = StringBuffer();
    err = StringBuffer();
  });

  tearDown(() async {
    await Directory(dir).delete(recursive: true);
  });

  Future<int> run(List<String> args) =>
      runDescribe(args, cwd: dir, out: out, err: err);

  File graphFile([String? inDir]) => File(p.join(inDir ?? dir, graphFileName));
  File source() => File(p.join(dir, 'lib', 'review.dart'));

  /// Changes the text of `lib/review.dart` with [change].
  Future<void> edit(String Function(String text) change) async =>
      source().writeAsString(change(await source().readAsString()));

  /// A line that does not compile, added to the end of `lib/review.dart`.
  Future<void> breakSource() => edit((text) => "${text}int broken = '';\n");

  /// The graph file describe gives, as the command writes it.
  Future<String> described() async {
    final graph = (await describePackage(dir)).graph!;
    return '${const JsonEncoder.withIndent('  ').convert(graph.toJson())}\n';
  }

  /// The names in the package directory that start with `.`: the temporary
  /// files of a write that was not finished.
  List<String> hidden(String inDir) => [
    for (final entity in Directory(inDir).listSync())
      if (p.basename(entity.path).startsWith('.')) p.basename(entity.path),
  ];

  test('writes the graph file, pretty, and only when it changed', () async {
    expect(await run([]), 0);
    expect(await graphFile().readAsString(), await described());
    expect(out.toString(), 'wrote nanoflow.graph.json\n');
    expect(err.toString(), isEmpty);
    expect(hidden(dir), isEmpty);

    final old = DateTime(2000);
    await graphFile().setLastModified(old);
    out.clear();
    expect(await run([]), 0);
    expect(await graphFile().lastModified(), old);
    expect(out.toString(), isEmpty);

    await edit((text) => text.replaceFirst("'collect'", "'gather'"));
    expect(await run([]), 0);
    expect(await graphFile().readAsString(), contains('"name": "gather"'));
    expect(await graphFile().readAsString(), await described());
    expect(out.toString(), 'wrote nanoflow.graph.json\n');
  });

  test('describes the package given by --package', () async {
    final parent = p.dirname(dir);
    final code = await runDescribe(
      ['--package', p.basename(dir)],
      cwd: parent,
      out: out,
      err: err,
    );
    expect(code, 0);
    expect(await graphFile().readAsString(), await described());
    expect(out.toString(), 'wrote ${p.join(p.basename(dir), graphFileName)}\n');

    out.clear();
    expect(await run(['--package', 'none']), 1);
    expect(err.toString(), 'no directory none\n');
    expect(out.toString(), isEmpty);
  });

  test('leaves the file alone while the sources do not compile', () async {
    expect(await run([]), 0);
    final text = await graphFile().readAsString();
    final old = DateTime(2000);
    await graphFile().setLastModified(old);
    await breakSource();
    out.clear();

    expect(await run([]), 1);
    expect(out.toString(), isEmpty);
    expect(
      err.toString(),
      matches(RegExp(r'^lib/review\.dart:\d+:\d+: .+\n$')),
    );
    expect(await graphFile().readAsString(), text);
    expect(await graphFile().lastModified(), old);
  });

  test('--check tells whether the file is what would be written', () async {
    expect(await run(['--check']), 1);
    expect(
      err.toString(),
      'nanoflow.graph.json is missing: run nanoflow_describe\n',
    );
    expect(graphFile().existsSync(), isFalse);

    await run([]);
    out.clear();
    err.clear();
    expect(await run(['--check']), 0);
    expect(out.toString(), isEmpty);
    expect(err.toString(), isEmpty);

    await edit((text) => '$text// edited\n');
    expect(await run(['--check']), 1);
    expect(
      err.toString(),
      'nanoflow.graph.json is stale: run nanoflow_describe\n',
    );

    await breakSource();
    err.clear();
    expect(await run(['--check']), 1);
    expect(
      err.toString(),
      matches(RegExp(r'^lib/review\.dart:\d+:\d+: .+\n$')),
    );
  });

  group('stamp', () {
    late File binary;

    setUp(() async {
      binary = File(p.join(dir, 'build', 'review'));
      await binary.parent.create();
      await binary.writeAsBytes([0x7f, 0x45, 0x4c, 0x46, 1, 2, 3]);
    });

    test('records the binary and copies the file next to it', () async {
      await run([]);
      out.clear();
      expect(await run(['stamp', 'build/review']), 0);
      final stamped = await graphFile().readAsString();
      final json = jsonDecode(stamped) as Map<String, Object?>;
      expect(json['builds'], {'review': bytesHash(await binary.readAsBytes())});
      // Nothing but builds differs from what describe writes.
      expect({
        ...json,
        'builds': <String, Object?>{},
      }, jsonDecode(await described()));
      expect(await graphFile(binary.parent.path).readAsString(), stamped);
      expect(
        out.toString(),
        'wrote nanoflow.graph.json\nwrote build/nanoflow.graph.json\n',
      );
      expect(hidden(binary.parent.path), isEmpty);

      // Builds stay sorted by name.
      await File(p.join(dir, 'build', 'review-arm')).writeAsBytes([9]);
      await File(p.join(dir, 'build', 'audit')).writeAsBytes([8]);
      expect(await run(['stamp', 'build/review-arm']), 0);
      expect(await run(['stamp', 'build/audit']), 0);
      final builds =
          (jsonDecode(await graphFile().readAsString())
                  as Map<String, Object?>)['builds']!
              as Map<String, Object?>;
      expect(builds.keys, ['audit', 'review', 'review-arm']);
      expect(builds['audit'], bytesHash([8]));

      // A stamped file is fresh, and describe keeps its builds while the
      // sources are the same.
      final text = await graphFile().readAsString();
      out.clear();
      expect(await run(['--check']), 0);
      expect(await run([]), 0);
      expect(await graphFile().readAsString(), text);
      expect(out.toString(), isEmpty);
      expect(err.toString(), isEmpty);

      // Once they change, the builds are of other code.
      await edit((text) => text.replaceFirst("'collect'", "'gather'"));
      expect(await run([]), 0);
      expect(await graphFile().readAsString(), await described());
    });

    test('refuses a file older than the sources', () async {
      await run([]);
      final text = await graphFile().readAsString();
      await edit((text) => '$text// edited\n');
      out.clear();

      expect(await run(['stamp', 'build/review']), 1);
      expect(
        err.toString(),
        'nanoflow.graph.json is stale: run nanoflow_describe before stamp\n',
      );
      expect(out.toString(), isEmpty);
      expect(await graphFile().readAsString(), text);
      expect(graphFile(binary.parent.path).existsSync(), isFalse);
    });

    test('refuses without a graph file or a binary', () async {
      expect(await run(['stamp', 'build/review']), 1);
      expect(
        err.toString(),
        'nanoflow.graph.json is missing: run nanoflow_describe before stamp\n',
      );
      expect(graphFile(binary.parent.path).existsSync(), isFalse);

      await run([]);
      final text = await graphFile().readAsString();
      err.clear();
      expect(await run(['stamp', 'build/none']), 1);
      expect(err.toString(), startsWith('cannot read build/none: '));
      expect(await graphFile().readAsString(), text);
    });
  });

  for (final (how, poll) in [
    ('watching the file system', null),
    ('polling', const Duration(milliseconds: 100)),
  ]) {
    test('--watch rewrites the file on every change, $how', () async {
      final stop = Completer<void>();
      final code = runDescribe(
        ['--watch'],
        cwd: dir,
        out: out,
        err: err,
        stop: stop.future,
        poll: poll,
      );
      const wrote = 'wrote nanoflow.graph.json\n';
      await until('the first write', () => out.toString() == wrote);

      await edit((text) => text.replaceFirst("'collect'", "'gather'"));
      await until('the rewrite', () => out.toString() == wrote * 2);
      expect(await graphFile().readAsString(), await described());

      // A source that does not compile: one line, the file stays.
      final text = await graphFile().readAsString();
      await breakSource();
      await until('the failure', () => err.toString().isNotEmpty);
      // A change that leaves the sources as they are describes nothing:
      // were they described again, they would fail again.
      await File(p.join(dir, 'lib', 'notes.txt')).writeAsString('notes');
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(
        err.toString(),
        matches(RegExp(r'^describe failed: lib/review\.dart:\d+:\d+: .+\n$')),
      );
      expect(await graphFile().readAsString(), text);

      stop.complete();
      expect(await code, 0);
      expect(out.toString(), wrote * 2);
    });
  }

  test('the program stops watching on SIGINT', () async {
    final process = await Process.start(Platform.resolvedExecutable, [
      'run',
      'nanoflow_describe',
      '--package',
      dir,
      '--watch',
    ]);
    addTearDown(() => process.kill(ProcessSignal.sigkill));
    final lines = <String>[];
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(lines.add);
    final errors = StringBuffer();
    process.stderr.transform(utf8.decoder).listen(errors.write);
    // `dart run` may build the program first, and say so.
    final wrote = 'wrote ${p.relative(graphFile().path)}';
    await until('the first write', () => lines.contains(wrote), seconds: 60);

    expect(process.kill(ProcessSignal.sigint), isTrue);
    expect(await process.exitCode.timeout(const Duration(seconds: 10)), 0);
    expect(lines.last, wrote);
    expect(errors.toString(), isEmpty);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('refuses arguments it does not know', () async {
    for (final args in [
      ['--verbose'],
      ['--watch', '--check'],
      ['stamp'],
      ['stamp', 'a', 'b'],
      ['--package'],
      ['extra'],
    ]) {
      err.clear();
      expect(await run(args), 2, reason: '$args');
      expect(err.toString(), contains('Usage: nanoflow_describe'));
      expect(out.toString(), isEmpty);
    }
    expect(graphFile().existsSync(), isFalse);
  });
}
