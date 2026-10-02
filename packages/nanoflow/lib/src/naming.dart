import 'dart:collection';
import 'dart:isolate';
import 'dart:mirrors';

import 'vertex.dart';

/// A top-level variable that holds a node: where the node's name comes from.
final class NodeVariable {
  NodeVariable({
    required this.name,
    required this.library,
    required this.path,
    required this.line,
    required this.column,
  });

  /// The variable's name: the node's name.
  final String name;

  /// The library that declares the variable.
  final Uri library;

  /// The file that declares the variable: an absolute path when the source
  /// is a file, the URI otherwise.
  final String path;

  /// Where in [path] the variable is declared.
  final int line;
  final int column;

  /// Declaration order: by library URI, then by place in the file.
  static int compare(NodeVariable a, NodeVariable b) {
    final byLibrary = '${a.library}'.compareTo('${b.library}');
    if (byLibrary != 0) return byLibrary;
    final byLine = a.line.compareTo(b.line);
    return byLine != 0 ? byLine : a.column.compareTo(b.column);
  }
}

/// Every top-level variable of the program whose type is a node, by the node
/// it holds, in declaration order.
///
/// Libraries of the Dart SDK are skipped. Reading a variable runs its
/// initializer if it has not run yet.
Map<Vertex<Object?, Object?>, List<NodeVariable>> nodeVariables() {
  final vertex = reflectClass(AnyVertex);
  final found = <(Vertex<Object?, Object?>, NodeVariable)>[];
  for (final library in currentMirrorSystem().libraries.values) {
    if (library.uri.isScheme('dart')) continue;
    for (final declaration in library.declarations.values) {
      if (declaration is! VariableMirror || !declaration.isTopLevel) continue;
      final type = declaration.type;
      if (type is! ClassMirror || !type.isSubclassOf(vertex)) continue;
      final value = library.getField(declaration.simpleName).reflectee;
      if (value is! Vertex<Object?, Object?>) continue;
      final location = declaration.location!;
      found.add((
        value,
        NodeVariable(
          name: MirrorSystem.getName(declaration.simpleName),
          library: library.uri,
          path: _pathOf(location.sourceUri),
          line: location.line,
          column: location.column,
        ),
      ));
    }
  }
  found.sort((a, b) => NodeVariable.compare(a.$2, b.$2));
  final byVertex =
      LinkedHashMap<Vertex<Object?, Object?>, List<NodeVariable>>.identity();
  for (final (vertex, variable) in found) {
    (byVertex[vertex] ??= []).add(variable);
  }
  return byVertex;
}

/// The path of the program's own source file: the root library's.
///
/// `Platform.script` is not it when the program runs as a package
/// executable (`dart run :graph`): then it is the snapshot pub built under
/// `.dart_tool`.
String programFile() => _pathOf(currentMirrorSystem().isolate.rootLibrary.uri);

String _pathOf(Uri source) {
  final resolved = source.isScheme('package')
      ? Isolate.resolvePackageUriSync(source) ?? source
      : source;
  return resolved.isScheme('file') ? resolved.toFilePath() : '$resolved';
}
