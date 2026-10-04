// The graph file of a package: its sources resolved by the analyzer, refused
// while they do not compile, then read by extract.dart, checked for side
// effects outside effects by side_effects.dart and hashed as the model hashes
// them (spec §6, §7.1).

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import 'extract.dart';
import 'side_effects.dart';

/// What [describePackage] read: the graph file, or why there is none.
final class DescribeResult {
  const DescribeResult({this.graph, this.errors = const []});

  /// The graph file; `null` when there are [errors].
  final GraphFile? graph;

  /// The compile errors of the sources (`path:line:column: message`, the path
  /// from the package root), or why the package has no name.
  final List<String> errors;
}

/// Reads every source of the package in [packageDir] (`packageSourcePaths`)
/// with resolved types, without running it, and builds the graph file.
///
/// The package is named [packageName], or by the `name:` of its
/// `pubspec.yaml`. A source with compile errors gives no graph, only the
/// errors.
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
    for (final file in paths.keys) {
      if (units.containsKey(file)) continue; // a part, read with its library
      final library = await session.getResolvedLibraryContaining(file);
      if (library is! ResolvedLibraryResult) {
        errors.add('${paths[file]}: cannot be resolved');
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
        }
      }
    }
    if (errors.isNotEmpty) return DescribeResult(errors: errors);
    final resolved = units.values.toList();
    final extracted = await extract(resolved, paths, session);
    final sources = await hashSources(root, sourcePaths);
    return DescribeResult(
      graph: GraphFile(
        format: graphFileFormat,
        package: name,
        fingerprint: fingerprintOf(sources),
        sources: sources,
        builds: const {},
        workflows: extracted.workflows,
        functions: extracted.functions,
        // Each once, by place.
        warnings: {
          ...extracted.warnings,
          ...sideEffectWarnings(resolved, paths, extracted.bodies),
        }.toList()..sort(_byPlace),
      ),
    );
  } finally {
    await collection.dispose();
  }
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
