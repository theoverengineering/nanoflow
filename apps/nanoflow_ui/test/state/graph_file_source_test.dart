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
