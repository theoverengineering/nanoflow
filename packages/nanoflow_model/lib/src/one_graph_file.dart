// The graph file of one graph, `<name>.graph.json` next to the Dart file the
// graph is declared in (file per graph design §2): its body, its warnings
// and the sources it was read from. A graph that serves as a node is a call
// whose `graph` is the path of its own file. Written by the describe tool,
// read by the workflow library and the UI, which put a graph and its
// subgraphs together as one graph file of format 3 (assembleGraphFile).

import 'package:collection/collection.dart';

import 'graph_file.dart';
import 'json_fields.dart';

const DeepCollectionEquality _deep = DeepCollectionEquality();

/// The format of the graph file of one graph.
const int oneGraphFileFormat = 4;

/// How the name of every graph file ends.
const String graphFileSuffix = '.graph.json';

/// The name of the graph file of the graph [name]: `<name>.graph.json`, each
/// character a file name cannot have (`/ \ : * ? " < > |` and control
/// characters) as `_`.
String graphFileNameOf(String name) =>
    '${name.replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f]'), '_')}'
    '$graphFileSuffix';

/// The graph file of one graph.
final class OneGraphFile {
  const OneGraphFile({
    required this.package,
    required this.name,
    required this.place,
    this.doc,
    required this.body,
    required this.warnings,
    required this.fingerprint,
    required this.sources,
    required this.builds,
  });

  /// Reads the graph file of one graph from its JSON form.
  ///
  /// Throws a [FormatException] whose message starts with the JSON path of
  /// the field that is missing or of the wrong kind
  /// (`body.nodes[2].graph: …`), or with `format` when the format is not
  /// [oneGraphFileFormat].
  factory OneGraphFile.fromJson(Map<String, Object?> json) {
    final format = readInt(json, 'format');
    if (format != oneGraphFileFormat) {
      throw FormatException(
        'format: expected $oneGraphFileFormat, the file is $format',
      );
    }
    return OneGraphFile(
      package: readString(json, 'package'),
      name: readString(json, 'name'),
      place: readStringOrNull(json, 'place'),
      doc: readStringOrNull(json, 'doc'),
      body: readNested(json, 'body', _readBody),
      warnings: readObjects(json, 'warnings', GraphWarning.fromJson),
      fingerprint: readString(json, 'fingerprint'),
      sources: readStringMap(json, 'sources'),
      builds: readStringMap(json, 'builds'),
    );
  }

  /// The name of the package.
  final String package;

  /// The name of the graph.
  final String name;

  /// `path:line` of the variable the graph is declared in, from the package
  /// root; `null` when unknown.
  final String? place;

  /// The doc comment over that variable, without its `///`; `null` when it
  /// has none.
  final String? doc;

  /// Its call nodes' `functions` hold one path each: the graph file of the
  /// subgraph, from the package root.
  final GraphBody body;

  /// What the describe tool could not draw in the graph and in the files of
  /// its [sources]; none has a function.
  final List<GraphWarning> warnings;

  /// `sha256:` and the hex fingerprint of [sources] (`fingerprintOf`).
  final String fingerprint;

  /// The hash of the graph's Dart file, and of every source of the package
  /// it imports, by its path from the package root.
  final Map<String, String> sources;

  /// The hash of every stamped binary by its file name.
  final Map<String, String> builds;

  /// The paths of the graph files of its subgraphs, from the package root,
  /// each once, in the order of its nodes.
  List<String> get subgraphs => {
    for (final node in body.nodes)
      if (node is CallNode) ...node.functions,
  }.toList();

  /// The graph as the function [id] of a graph file of format 3.
  GraphFunction asFunction(String id) =>
      GraphFunction(id: id, name: name, place: place, doc: doc, body: body);

  Map<String, Object?> toJson() => {
    'format': oneGraphFileFormat,
    'package': package,
    'name': name,
    'place': place,
    'doc': doc,
    'body': {
      'nodes': [
        for (final node in body.nodes)
          if (node is CallNode)
            {
              'id': node.id,
              'kind': 'call',
              'graph': node.functions.single,
              'place': node.place,
            }
          else
            node.toJson(),
      ],
      'edges': [for (final edge in body.edges) edge.toJson()],
    },
    'warnings': [
      for (final warning in warnings)
        {'place': warning.place, 'message': warning.message},
    ],
    'fingerprint': fingerprint,
    'sources': {...sources},
    'builds': {...builds},
  };

  @override
  bool operator ==(Object other) =>
      other is OneGraphFile &&
      other.package == package &&
      other.name == name &&
      other.place == place &&
      other.doc == doc &&
      other.body == body &&
      _deep.equals(other.warnings, warnings) &&
      other.fingerprint == fingerprint &&
      _deep.equals(other.sources, sources) &&
      _deep.equals(other.builds, builds);

  @override
  int get hashCode => Object.hash(
    package,
    name,
    place,
    doc,
    body,
    _deep.hash(warnings),
    fingerprint,
    _deep.hash(sources),
    _deep.hash(builds),
  );

  @override
  String toString() =>
      'OneGraphFile(package: $package, name: $name, place: $place, '
      'doc: $doc, body: $body, warnings: $warnings, '
      'fingerprint: $fingerprint, sources: $sources, builds: $builds)';
}

/// The body of a graph file of one graph: a call's `graph` is read as its
/// one function.
GraphBody _readBody(Map<String, Object?> json) => GraphBody(
  nodes: readObjects(json, 'nodes', (node) {
    if (node['kind'] != 'call') return GraphNode.fromJson(node);
    return CallNode(
      id: readString(node, 'id'),
      place: readStringOrNull(node, 'place'),
      functions: [readString(node, 'graph')],
    );
  }),
  edges: readObjects(json, 'edges', GraphEdge.fromJson),
);

/// The graph file [files] has at [path] and the graph files of its
/// subgraphs, and of theirs, as one graph file of format 3, as a session's
/// snapshot keeps them (file per graph design §4): each graph a function
/// whose id is the path of its file, the graph at [path] the workflow; the
/// package, fingerprint, sources and builds of its file, the warnings of
/// every file, each once. A subgraph [files] does not have is left out: its
/// call has no body to open. `null` when [files] has no file at [path].
GraphFile? assembleGraphFile(String path, Map<String, OneGraphFile> files) {
  final main = files[path];
  if (main == null) return null;
  final reached = <String>[];
  void reach(String path) {
    final file = files[path];
    if (file == null || reached.contains(path)) return;
    reached.add(path);
    file.subgraphs.forEach(reach);
  }

  reach(path);
  return GraphFile(
    format: graphFileFormat,
    package: main.package,
    fingerprint: main.fingerprint,
    sources: main.sources,
    builds: main.builds,
    workflows: [path],
    functions: {
      for (final path in reached) path: files[path]!.asFunction(path),
    },
    warnings: {for (final path in reached) ...files[path]!.warnings}.toList(),
  );
}
