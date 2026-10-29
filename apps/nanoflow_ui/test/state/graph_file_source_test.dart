import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/graph_file_source.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

void main() {
  late Directory dir;
  late String file;
  late GraphFileSource source;
  late int notified;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nanoflow_graph_file');
    file = p.join(dir.path, graphFileName);
    source = GraphFileSource(
      file: file,
      pollInterval: const Duration(milliseconds: 20),
    );
    notified = 0;
    source.addListener(() => notified++);
  });

  tearDown(() {
    source.dispose();
    dir.deleteSync(recursive: true);
  });

  /// Writes [text] to the graph file the way describe does: under another
  /// name, renamed into place.
  void write(String text) {
    final temporary = File(p.join(dir.path, '.$graphFileName.tmp'))
      ..writeAsStringSync(text);
    temporary.renameSync(file);
  }

  String json(GraphFile graph) =>
      const JsonEncoder.withIndent('  ').convert(graph.toJson());

  test('gives the graph file as it is when started', () async {
    write(json(reviewGraphFile()));
    await source.start();
    expect(source.graph, reviewGraphFile());
    expect(source.error, isNull);
    expect(source.fileMissing, isFalse);
    expect(notified, 1);
  });

  test('gives the graph file again once it changes', () async {
    write(json(reviewGraphFile()));
    await source.start();

    write(json(reviewGraphFile(reviewEffect: 'gather')));
    await _until(() => source.graph == reviewGraphFile(reviewEffect: 'gather'));
    expect(notified, 2);

    // Written in place, as an editor may.
    File(file).writeAsStringSync(json(reviewGraphFile(reviewEffect: 'take')));
    await _until(() => source.graph == reviewGraphFile(reviewEffect: 'take'));
  });

  test(
    'a file that is not JSON is an error; the last graph read stays',
    () async {
      write(json(reviewGraphFile()));
      await source.start();

      write('{"format": 2,');
      await _until(() => source.error != null);
      expect(source.error, contains('Unexpected end of input'));
      expect(source.graph, reviewGraphFile());

      write(json(reviewGraphFile(reviewEffect: 'gather')));
      await _until(() => source.error == null);
      expect(source.graph, reviewGraphFile(reviewEffect: 'gather'));
    },
  );

  test('JSON that is not a graph file is an error that says where', () async {
    final broken = graphFileJson()..remove('workflows');
    write(jsonEncode(broken));
    await source.start();
    expect(source.graph, isNull);
    expect(source.error, startsWith('workflows'));

    write('[]');
    await _until(() => source.error == 'the file is not a JSON object');
  });

  test('a file deleted while open: the last graph stays, the file is '
      'missing until it is back', () async {
    write(json(reviewGraphFile()));
    await source.start();

    File(file).deleteSync();
    await _until(() => source.fileMissing);
    expect(source.graph, reviewGraphFile());

    write(json(reviewGraphFile(reviewEffect: 'gather')));
    await _until(() => !source.fileMissing);
    expect(source.graph, reviewGraphFile(reviewEffect: 'gather'));
  });

  test('a file not there when started is missing', () async {
    await source.start();
    expect(source.fileMissing, isTrue);
    expect(source.graph, isNull);

    write(json(reviewGraphFile()));
    await _until(() => source.graph != null);
    expect(source.fileMissing, isFalse);
  });

  test('a file written again as it was tells nobody', () async {
    write(json(reviewGraphFile()));
    await source.start();
    write(json(reviewGraphFile()));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(notified, 1);
  });

  test('stops looking once disposed', () async {
    write(json(reviewGraphFile()));
    final disposed = GraphFileSource(
      file: file,
      pollInterval: const Duration(milliseconds: 20),
    );
    await disposed.start();
    disposed.dispose();
    write(json(reviewGraphFile(reviewEffect: 'gather')));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(disposed.graph, reviewGraphFile());
  });

  group("a graph's own file", () {
    late String root;
    late GraphFileSource own;

    /// The graph file of the graph [name] whose effect is [effect], calling
    /// the graph files [calls].
    OneGraphFile graphOf(
      String name, {
      String effect = 'collect',
      List<String> calls = const [],
    }) => OneGraphFile(
      package: 'review_example',
      name: name,
      place: 'lib/review.dart:1',
      body: GraphBody(
        nodes: [
          EffectNode(id: '1', place: 'lib/review.dart:2', name: effect),
          for (final (i, call) in calls.indexed)
            CallNode(
              id: '${i + 2}',
              place: 'lib/review.dart:3',
              functions: [call],
            ),
        ],
        edges: const [],
      ),
      warnings: const [],
      fingerprint: 'sha256:0',
      sources: const {},
      builds: const {},
    );

    /// Writes [graph] to [path] from the package root, as describe does.
    void put(String path, OneGraphFile graph) {
      final target = File(p.joinAll([root, ...path.split('/')]))
        ..parent.createSync(recursive: true);
      File('${target.path}.tmp')
        ..writeAsStringSync(jsonEncode(graph.toJson()))
        ..renameSync(target.path);
    }

    setUp(() {
      root = p.join(dir.path, 'review');
      File(p.join(root, 'pubspec.yaml')).createSync(recursive: true);
      own = GraphFileSource(
        file: p.join(root, 'lib', 'review.graph.json'),
        pollInterval: const Duration(milliseconds: 20),
      );
    });

    tearDown(() => own.dispose());

    const review = 'lib/review.graph.json';
    const polish = 'lib/src/polish.graph.json';

    test('is read with the files of its subgraphs, put together', () async {
      final files = {
        review: graphOf('review', calls: [polish]),
        polish: graphOf('polish', effect: 'fix'),
      };
      files.forEach(put);
      await own.start();
      expect(own.graph, assembleGraphFile(review, files));
      expect(own.oneGraph, isTrue);
      expect(own.error, isNull);
    });

    test("is read again when a subgraph's file changes, or comes", () async {
      put(review, graphOf('review', calls: [polish]));
      await own.start();
      expect(own.graph!.functions.keys, [review]);

      final files = {
        review: graphOf('review', calls: [polish]),
        polish: graphOf('polish', effect: 'fix'),
      };
      put(polish, files[polish]!);
      await _until(() => own.graph == assembleGraphFile(review, files));

      files[polish] = graphOf('polish', effect: 'mend');
      put(polish, files[polish]!);
      await _until(() => own.graph == assembleGraphFile(review, files));
    });

    test("says what is wrong with it, but not with a subgraph's", () async {
      put(review, graphOf('review', calls: [polish]));
      File(p.join(root, 'lib', 'src', 'polish.graph.json'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{}');
      await own.start();
      expect(own.graph!.functions.keys, [review]);
      expect(own.error, isNull);

      File(own.file).writeAsStringSync('{"format": 4}');
      await _until(() => own.error != null);
      expect(own.error, 'package: missing');
    });
  });

  group('readGraphFile', () {
    test('reads a snapshot of the graph file', () {
      expect(readGraphFile(graphFileJson()), reviewGraphFile());
    });

    test('reads what is not a graph file as null', () {
      expect(readGraphFile(null), isNull);
      expect(readGraphFile('graph'), isNull);
      expect(readGraphFile(graphFileJson()..remove('format')), isNull);
    });

    test('reads the same snapshot once', () {
      final snapshot = graphFileJson();
      expect(readGraphFile(snapshot), same(readGraphFile(snapshot)));
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
