// The graph files of a package (file per graph design §2–§3): its sources
// resolved by the analyzer, read by extract.dart, their routes checked for
// side effects outside effects by side_effects.dart; then each graph given a
// file of its own, next to its Dart file, with its sources — its Dart file
// and what it imports from the package, by chain — hashed as the model
// hashes them (spec §6.2). A graph whose sources do not compile has no file;
// the others do.

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import 'extract.dart';
import 'side_effects.dart';

/// What [describePackage] read: the graphs and their files, and the compile
/// errors that kept graphs out.
final class DescribeResult {
  const DescribeResult({
    this.graphs = const {},
    this.warnings = const [],
    this.files = const {},
    this.errors = const [],
  });

  /// The graphs whose sources compile, by id (`path#variable`), sorted by id;
  /// a call's function is the id of its graph.
  final Map<String, GraphFunction> graphs;

  /// What could not be drawn in the sources read, each once, by place, with
  /// the id of the graph whose declaration (`Graph(…)`) holds it: its
  /// `function`; `null` for none.
  final List<GraphWarning> warnings;

  /// The graph file of each of [graphs], by its path from the package root,
  /// sorted by path.
  final Map<String, OneGraphFile> files;

  /// The compile errors of the sources (`path:line:column: message`, the path
  /// from the package root), or why the package has no name.
  final List<String> errors;
}

/// Reads every source of the package in [packageDir] (`packageSourcePaths`)
/// with resolved types, without running it, and builds the graph file of
/// each graph whose sources compile.
///
/// The package is named [packageName], or by the `name:` of its
/// `pubspec.yaml`; without a name there are no graphs, only the error.
Future<DescribeResult> describePackage(
  String packageDir, {
  String? packageName,
}) async {
  final root = p.normalize(p.absolute(packageDir));
  final name = packageName ?? await _pubspecName(root);
  if (name == null) {
    return DescribeResult(
      errors: ['${p.join(root, 'pubspec.yaml')}: no package name'],
    );
  }
  final sourcePaths = await packageSourcePaths(root);
  // The path from the package root of every source by its absolute path.
  final paths = {
    for (final path in sourcePaths) p.joinAll([root, ...path.split('/')]): path,
  };
  final collection = AnalysisContextCollection(includedPaths: [root]);
  try {
    final session = collection.contextFor(root).currentSession;
    final units = <String, ResolvedUnitResult>{};
    final errors = <String>[];
    // The sources with compile errors, by their path from the package root.
    final broken = <String>{};
    for (final file in paths.keys) {
      if (units.containsKey(file)) continue; // a part, read with its library
      final library = await session.getResolvedLibraryContaining(file);
      if (library is! ResolvedLibraryResult) {
        errors.add('${paths[file]}: cannot be resolved');
        broken.add(paths[file]!);
        continue;
      }
      for (final unit in library.units) {
        final path = paths[unit.path];
        if (path == null) continue; // a part outside the sources
        units[unit.path] = unit;
        for (final diagnostic in unit.diagnostics) {
          if (diagnostic.severity != Severity.error) continue;
          final at = unit.lineInfo.getLocation(diagnostic.offset);
          errors.add(
            '$path:${at.lineNumber}:${at.columnNumber}: ${diagnostic.message}',
          );
          broken.add(path);
        }
      }
    }
    final imported = <LibraryElement, Set<String>>{};
    Set<String> sourcesOf(LibraryElement library) =>
        imported[library] ??= _sourcesOf(library, paths);
    // A source is read when it compiles with all it imports: a graph whose
    // sources do not compile keeps the file it has.
    final read = [
      for (final unit in units.values)
        if (!sourcesOf(unit.libraryElement).any(broken.contains)) unit,
    ];
    final extracted = extract(read, paths);
    final hashes = await hashSources(root, sourcePaths);
    // Each once, by place, with the graph it is in.
    final warnings = {
      for (final warning in {
        ...extracted.warnings,
        ...sideEffectWarnings(read, paths, extracted.routes),
      })
        if (_split(warning.place!) case (final path, final line))
          GraphWarning(
            place: warning.place,
            message: warning.message,
            function: extracted.functionAt(path, line),
          ),
    }.toList()..sort(_byPlace);
    final libraries = {
      for (final unit in read) paths[unit.path]!: unit.libraryElement,
    };
    return DescribeResult(
      graphs: extracted.functions,
      warnings: warnings,
      files: _files(
        name,
        extracted.functions,
        warnings,
        sourcesOf: (path) => {
          for (final source in sourcesOf(libraries[path]!).toList()..sort())
            source: hashes[source]!,
        },
      ),
      errors: errors,
    );
  } finally {
    await collection.dispose();
  }
}

/// The graph file of each of [graphs] of the package [package], by its path:
/// next to the Dart file of the graph, named by the graph — the first by id
/// takes a path two graphs share —; a call goes to the path of its graph's
/// file. Its sources are what [sourcesOf] gives for its Dart file; its
/// warnings, those of [warnings] in its declaration, and those in none that
/// are in its sources.
Map<String, OneGraphFile> _files(
  String package,
  Map<String, GraphFunction> graphs,
  List<GraphWarning> warnings, {
  required Map<String, String> Function(String path) sourcesOf,
}) {
  String dartFileOf(String id) => id.substring(0, id.lastIndexOf('#'));
  final pathOf = {
    for (final MapEntry(key: id, value: graph) in graphs.entries)
      id: p.url.join(
        p.url.dirname(dartFileOf(id)),
        graphFileNameOf(graph.name),
      ),
  };
  final files = <String, OneGraphFile>{};
  for (final MapEntry(key: id, value: graph) in graphs.entries) {
    final path = pathOf[id]!;
    if (files.containsKey(path)) continue;
    final sources = sourcesOf(dartFileOf(id));
    files[path] = OneGraphFile(
      package: package,
      name: graph.name,
      place: graph.place,
      doc: graph.doc,
      body: GraphBody(
        nodes: [
          for (final node in graph.body.nodes)
            if (node is CallNode)
              CallNode(
                id: node.id,
                place: node.place,
                functions: [for (final f in node.functions) pathOf[f] ?? f],
              )
            else
              node,
        ],
        edges: graph.body.edges,
      ),
      warnings: [
        for (final warning in warnings)
          if (warning.function == id ||
              (warning.function == null &&
                  sources.containsKey(_split(warning.place!).$1)))
            GraphWarning(place: warning.place, message: warning.message),
      ],
      fingerprint: fingerprintOf(sources),
      sources: sources,
      builds: const {},
    );
  }
  return {for (final path in files.keys.toList()..sort()) path: files[path]!};
}

/// The sources of the package [library] is made of and imports or exports,
/// by chain, by their paths from the package root; [paths] gives those of
/// all the sources by their absolute paths.
Set<String> _sourcesOf(LibraryElement library, Map<String, String> paths) {
  final sources = <String>{};
  final seen = <LibraryElement>{library};
  final pending = [library];
  while (pending.isNotEmpty) {
    for (final fragment in pending.removeLast().fragments) {
      final path = paths[fragment.source.fullName];
      if (path == null) continue; // not a source of the package
      sources.add(path);
      for (final other in [
        for (final import in fragment.libraryImports) import.importedLibrary,
        for (final export in fragment.libraryExports) export.exportedLibrary,
      ]) {
        if (other != null && seen.add(other)) pending.add(other);
      }
    }
  }
  return sources;
}

/// By path, then by line, then by message.
int _byPlace(GraphWarning a, GraphWarning b) {
  final (pathA, lineA) = _split(a.place!);
  final (pathB, lineB) = _split(b.place!);
  final byPath = pathA.compareTo(pathB);
  if (byPath != 0) return byPath;
  final byLine = lineA.compareTo(lineB);
  return byLine != 0 ? byLine : a.message.compareTo(b.message);
}

(String, int) _split(String place) {
  final colon = place.lastIndexOf(':');
  return (place.substring(0, colon), int.parse(place.substring(colon + 1)));
}

/// The `name:` of `<root>/pubspec.yaml`, or `null`.
Future<String?> _pubspecName(String root) async {
  final String text;
  try {
    text = await File(p.join(root, 'pubspec.yaml')).readAsString();
  } on FileSystemException {
    return null;
  }
  return RegExp(
    r'''^name:\s*['"]?(\w+)['"]?\s*(?:#.*)?$''',
    multiLine: true,
  ).firstMatch(text)?.group(1);
}
