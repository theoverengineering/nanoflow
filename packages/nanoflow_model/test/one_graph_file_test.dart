import 'dart:convert';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:test/test.dart';

const String _generate = 'lib/src/generate/generateIdeas.graph.json';
const String _compress = 'lib/src/compress/compressIdea.graph.json';
const String _shorten = 'lib/src/compress/shorten.graph.json';

/// The graph file of one graph whose node 2 calls the graphs [calls], with
/// [warnings]; every key in the order of the spec.
Map<String, Object?> _fileJson(
  String name, {
  List<String> calls = const [],
  List<Object?> warnings = const [],
}) => {
  'format': 4,
  'package': 'ideas_flow',
  'name': name,
  'place': 'lib/src/$name.dart:3',
  'doc': 'Does $name.',
  'body': {
    'nodes': [
      {
        'id': '1',
        'kind': 'effect',
        'name': 'survey',
        'place': 'lib/src/$name.dart:4',
        'doc': null,
      },
      for (final (i, call) in calls.indexed)
        {
          'id': '${i + 2}',
          'kind': 'call',
          'graph': call,
          'place': 'lib/src/$name.dart:5',
        },
    ],
    'edges': [
      {'from': null, 'to': '1', 'label': null},
      {'from': '1', 'to': null, 'label': null},
    ],
  },
  'warnings': warnings,
  'fingerprint': 'sha256:f1',
  'sources': {'lib/src/$name.dart': 'sha256:aa'},
  'builds': {'ideas': 'sha256:b1'},
};

OneGraphFile _file(
  String name, {
  List<String> calls = const [],
  List<Object?> warnings = const [],
}) => OneGraphFile.fromJson(_fileJson(name, calls: calls, warnings: warnings));

Map<String, Object?> _warning(String place, String message) => {
  'place': place,
  'message': message,
};

void main() {
  test('names the file of a graph by the graph', () {
    expect(oneGraphFileFormat, 4);
    expect(graphFileNameOf('generateIdeas'), 'generateIdeas.graph.json');
    expect(graphFileNameOf('a/b: c?'), 'a_b_ c_.graph.json');
  });

  group('OneGraphFile', () {
    test('round trips through JSON, keys in the order of the spec', () {
      final json = _fileJson(
        'generateIdeas',
        calls: [_compress],
        warnings: [_warning('lib/src/generateIdeas.dart:9', 'odd')],
      );
      final file = OneGraphFile.fromJson(json);
      expect(OneGraphFile.fromJson(file.toJson()), file);
      expect(jsonEncode(file.toJson()), jsonEncode(json));
    });

    test('reads a call as the path of its graph file', () {
      final file = _file('generateIdeas', calls: [_compress]);
      expect(
        file.body.nodes[1],
        const CallNode(
          id: '2',
          place: 'lib/src/generateIdeas.dart:5',
          functions: [_compress],
        ),
      );
      expect(file.subgraphs, [_compress]);
    });

    test('lists each subgraph once', () {
      expect(_file('a', calls: [_compress, _shorten, _compress]).subgraphs, [
        _compress,
        _shorten,
      ]);
    });

    test('reads a warning without a function', () {
      final file = _file('a', warnings: [_warning('lib/a.dart:1', 'odd')]);
      expect(file.warnings, [
        const GraphWarning(place: 'lib/a.dart:1', message: 'odd'),
      ]);
    });

    test('refuses another format', () {
      expect(
        () => OneGraphFile.fromJson({..._fileJson('a'), 'format': 3}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'format: expected 4, the file is 3',
          ),
        ),
      );
    });

    test('names the path of a call without its graph', () {
      final json = _fileJson('a', calls: [_compress]);
      final nodes = (json['body']! as Map)['nodes'] as List;
      (nodes[1] as Map).remove('graph');
      expect(
        () => OneGraphFile.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'body.nodes[1].graph: missing',
          ),
        ),
      );
    });

    test('is not read as a graph file of format 3', () {
      expect(
        () => GraphFile.fromJson(_fileJson('a')),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'format: expected 3, the file is 4',
          ),
        ),
      );
    });
  });

  group('assembleGraphFile', () {
    final files = {
      _generate: _file(
        'generateIdeas',
        calls: [_compress],
        warnings: [_warning('lib/src/generateIdeas.dart:9', 'odd')],
      ),
      _compress: _file(
        'compressIdea',
        calls: [_shorten, _generate],
        warnings: [_warning('lib/src/compressIdea.dart:7', 'odd too')],
      ),
      _shorten: _file('shorten'),
      'lib/src/other.graph.json': _file('other'),
    };

    test('is the graph and what it calls, by the paths of their files', () {
      final graph = assembleGraphFile(_generate, files)!;
      expect(graph.format, 3);
      expect(graph.workflows, [_generate]);
      expect(graph.functions.keys, [_generate, _compress, _shorten]);
      expect(
        graph.functions[_compress],
        files[_compress]!.asFunction(_compress),
      );
      expect(graph.workflowNamed('generateIdeas')?.id, _generate);
    });

    test('takes the package, fingerprint, sources and builds of its file', () {
      final graph = assembleGraphFile(_compress, files)!;
      final file = files[_compress]!;
      expect(
        (graph.package, graph.fingerprint, graph.sources, graph.builds),
        (file.package, file.fingerprint, file.sources, file.builds),
      );
    });

    test('has the warnings of every file, each once', () {
      expect(assembleGraphFile(_generate, files)!.warnings, [
        const GraphWarning(
          place: 'lib/src/generateIdeas.dart:9',
          message: 'odd',
        ),
        const GraphWarning(
          place: 'lib/src/compressIdea.dart:7',
          message: 'odd too',
        ),
      ]);
    });

    test('leaves out a subgraph without a file', () {
      final graph = assembleGraphFile(_generate, {
        _generate: files[_generate]!,
      })!;
      expect(graph.functions.keys, [_generate]);
    });

    test('is none without the file of the graph', () {
      expect(assembleGraphFile('lib/none.graph.json', files), isNull);
    });

    test('is read back as it was written', () {
      final graph = assembleGraphFile(_generate, files)!;
      expect(GraphFile.fromJson(graph.toJson()), graph);
    });
  });
}
