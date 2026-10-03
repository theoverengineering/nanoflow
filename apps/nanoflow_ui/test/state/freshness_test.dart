import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/freshness.dart';
import 'package:nanoflow_ui/state/graph_file_source.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('nanoflow_fresh'));
  tearDown(() => dir.deleteSync(recursive: true));

  void write(String path, String text) => File(p.join(dir.path, path))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);

  /// The graph file describe would write for the sources in [dir] now, with
  /// [builds].
  Future<GraphFile> describe({Map<String, String> builds = const {}}) async {
    final sources = await hashSources(
      dir.path,
      await packageSourcePaths(dir.path),
    );
    return GraphFile.fromJson({
      ...graphFileJson(fingerprint: fingerprintOf(sources), builds: builds),
      'sources': sources,
    });
  }

  group('sources next to the graph file', () {
    setUp(() {
      write('lib/review.dart', 'void review() {}\n');
      write('bin/main.dart', 'void main() {}\n');
    });

    test('unchanged: fresh', () async {
      final freshness = await checkFreshness(await describe(), dir.path);
      expect(freshness.stale, isFalse);
      expect(freshness.changed, isEmpty);
    });

    test('one edited: stale, with its path', () async {
      final graph = await describe();
      write('lib/review.dart', 'void review() { print(1); }\n');
      final freshness = await checkFreshness(graph, dir.path);
      expect(freshness.stale, isTrue);
      expect(freshness.changed, ['lib/review.dart']);
    });

    test('one gone: stale, with its path', () async {
      final graph = await describe();
      File(p.join(dir.path, 'bin/main.dart')).deleteSync();
      final freshness = await checkFreshness(graph, dir.path);
      expect(freshness.stale, isTrue);
      expect(freshness.changed, ['bin/main.dart']);
    });

    test('with other line endings: fresh', () async {
      final graph = await describe();
      write('lib/review.dart', 'void review() {}\r\n');
      expect((await checkFreshness(graph, dir.path)).stale, isFalse);
    });

    test('an edit undone: fresh again', () async {
      final graph = await describe();
      final hashes = FileHashes();
      write('lib/review.dart', 'void review() { print(1); }\n');
      expect(
        (await checkFreshness(graph, dir.path, hashes: hashes)).stale,
        isTrue,
      );
      write('lib/review.dart', 'void review() {}\n');
      expect(
        (await checkFreshness(graph, dir.path, hashes: hashes)).stale,
        isFalse,
      );
    });
  });

  test('a graph file without its sources next to it: fresh, nothing '
      'compared', () async {
    final freshness = await checkFreshness(reviewGraphFile(), dir.path);
    expect(freshness.stale, isFalse);
    expect(freshness.changed, isEmpty);
  });

  group('a binary next to the graph file listed in builds', () {
    test('whose bytes hash as listed: fresh', () async {
      write('review', 'binary 1');
      final graph = reviewGraphFile(
        builds: {'review': bytesHash(utf8.encode('binary 1'))},
      );
      final freshness = await checkFreshness(graph, dir.path);
      expect(freshness.stale, isFalse);
      expect(freshness.changed, isEmpty);
    });

    test('built again since: stale, with its name', () async {
      write('review', 'binary 2');
      final graph = reviewGraphFile(
        builds: {
          'review': bytesHash(utf8.encode('binary 1')),
          'other': bytesHash(utf8.encode('not here')),
        },
      );
      final freshness = await checkFreshness(graph, dir.path);
      expect(freshness.stale, isTrue);
      expect(freshness.changed, ['review']);
    });
  });

  group('the code of a session', () {
    final graph = reviewGraphFile(
      fingerprint: 'sha256:sources',
      builds: {'review': 'sha256:binary'},
    );

    test('the fingerprint of the graph: matches', () {
      expect(checkCode('sha256:sources', graph), CodeCheck.matches);
    });

    test('a build of the graph: matches', () {
      expect(checkCode('sha256:binary', graph), CodeCheck.matches);
    });

    test('anything else: other code', () {
      expect(checkCode('sha256:edited', graph), CodeCheck.otherCode);
    });

    test('none recorded: not checked', () {
      expect(checkCode(null, graph), CodeCheck.notChecked);
    });
  });

  group('watching', () {
    late GraphFileSource source;
    late FreshnessWatch watch;

    setUp(() async {
      write('lib/review.dart', 'void review() {}\n');
      final graph = await describe();
      write(graphFileName, jsonEncode(graph.toJson()));
      source = GraphFileSource(
        file: p.join(dir.path, graphFileName),
        pollInterval: const Duration(milliseconds: 20),
      );
      watch = FreshnessWatch(
        source,
        interval: const Duration(milliseconds: 20),
      );
      await source.start();
      watch.start();
    });

    tearDown(() {
      watch.dispose();
      source.dispose();
    });

    test('checks the graph file once it is read, and again as the sources '
        'change', () async {
      await _until(() => watch.freshness != null);
      expect(watch.freshness!.stale, isFalse);

      var notified = 0;
      watch.addListener(() => notified++);
      write('lib/review.dart', 'void review() { print(1); }\n');
      await _until(() => watch.freshness!.stale);
      expect(watch.freshness!.changed, ['lib/review.dart']);
      expect(notified, 1);
    });

    test('checks a new graph file at once', () async {
      await _until(() => watch.freshness != null);
      write('lib/review.dart', 'void review() { print(1); }\n');
      await _until(() => watch.freshness!.stale);

      write(graphFileName, jsonEncode((await describe()).toJson()));
      await _until(() => !watch.freshness!.stale);
    });
  });
}

/// Waits until [done] holds, looking every few milliseconds.
Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('waited too long');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
