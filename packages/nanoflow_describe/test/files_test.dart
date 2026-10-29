// The graph file of each graph (file per graph design §2): next to its Dart
// file and named by the graph, its sources what that file imports from the
// package by chain, a call the path of its graph's file, the warnings of its
// declaration and of its sources outside any graph's.

import 'package:nanoflow_describe/nanoflow_describe.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:test/test.dart';

import 'support.dart';

const _compress = 'lib/src/compress/compressIdea.graph.json';
const _generate = 'lib/src/generate/generateIdeas.graph.json';
const _another = 'lib/src/other/another.graph.json';
const _other = 'lib/src/other/other.graph.json';

/// The warning of the node named by a constant, in no graph's declaration.
const _rank = GraphWarning(
  place: 'lib/src/nodes.dart:13',
  message: 'node name is not a string literal',
);

void main() {
  late Map<String, OneGraphFile> files;

  setUpAll(() async {
    final result = await describePackage(
      fixture('graph_files'),
      packageName: 'graph_files',
    );
    expect(result.errors, isEmpty);
    files = result.files;
  });

  test('gives each graph a file next to its Dart file, named by it', () {
    expect(files.keys, [_compress, _generate, _another, _other]);
    expect(files[_generate]!.name, 'generateIdeas');
    expect(files[_generate]!.package, 'graph_files');
    expect(files[_generate]!.place, 'lib/src/generate/generate.dart:10');
    expect(files[_generate]!.doc, 'Thinks up an idea and makes it shorter.');
    expect(files[_generate]!.builds, isEmpty);
  });

  test('takes as sources the Dart file of the graph, the parts of its '
      'library and what they import and export from the package, by '
      'chain', () async {
    expect(files[_generate]!.sources.keys, [
      'lib/src/compress/compress.dart',
      'lib/src/generate/generate.dart',
      'lib/src/generate/ideas.dart',
      'lib/src/more_nodes.dart',
      'lib/src/nodes.dart',
    ]);
    expect(files[_compress]!.sources.keys, [
      'lib/src/compress/compress.dart',
      'lib/src/more_nodes.dart',
      'lib/src/nodes.dart',
    ]);
    expect(files[_other]!.sources.keys, [
      'lib/src/more_nodes.dart',
      'lib/src/nodes.dart',
      'lib/src/other/other.dart',
    ]);
    final dir = fixture('graph_files');
    for (final file in files.values) {
      expect(
        file.sources,
        await hashSources(dir, file.sources.keys),
        reason: file.name,
      );
      expect(file.fingerprint, fingerprintOf(file.sources), reason: file.name);
    }
  });

  test('calls a subgraph by the path of its file', () {
    expect(files[_generate]!.body.nodes, [
      const EffectNode(
        id: '1',
        place: 'lib/src/generate/generate.dart:11',
        name: 'survey',
      ),
      const CallNode(
        id: '2',
        place: 'lib/src/generate/generate.dart:11',
        functions: [_compress],
      ),
    ]);
    expect(files[_generate]!.subgraphs, [_compress]);
  });

  test('has the warnings of its declaration and of its sources outside any '
      "graph's, not those of another graph", () {
    expect(files[_compress]!.warnings, [
      const GraphWarning(
        place: 'lib/src/compress/compress.dart:9',
        message: 'side effect outside an effect: DateTime.now()',
      ),
      _rank,
    ]);
    // compressIdea's own are in its file.
    expect(files[_generate]!.warnings, [_rank]);
    expect(files[_another]!.warnings, [
      _rank,
      const GraphWarning(
        place: 'lib/src/other/other.dart:9',
        message: 'side effect outside an effect: DateTime.now()',
      ),
    ]);
    // another's, though in the same Dart file, are not other's.
    expect(files[_other]!.warnings, [_rank]);
  });

  test('a graph with what it calls is what the files assemble to', () {
    final graph = assembleGraphFile(_generate, files)!;
    expect(graph.functions.keys, [_generate, _compress]);
    expect(graph.warnings, [_rank, files[_compress]!.warnings.first]);
  });
}
