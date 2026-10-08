// What the tests of extraction share: the fixture packages and the graph
// file each must give.

import 'dart:convert';

import 'package:nanoflow_describe/nanoflow_describe.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A fixture package under `test/fixtures/`: `lib/`, `bin/`, no pubspec.
String fixture(String name) => p.join('test', 'fixtures', name);

/// The graph file of the fixture [name], whose package is called [name].
Future<Map<String, Object?>> describeFixture(String name) async {
  final result = await describePackage(fixture(name), packageName: name);
  expect(result.errors, isEmpty);
  return result.graph!.toJson();
}

/// [functions] as the file has them: `doc: null` on a function and on an
/// effect whose expectation gives none, in the place the file has it — the
/// fixtures document only what their tests say.
Map<String, Object?> withDocs(Map<String, Object?> functions) => {
  for (final MapEntry(key: id, value: function) in functions.entries)
    id: {
      for (final MapEntry(:key, :value)
          in (function! as Map<String, Object?>).entries)
        if (key == 'body') ...{
          'doc': (function as Map)['doc'],
          key: _bodyWithDocs(value),
        } else if (key != 'doc')
          key: value,
    },
};

Object? _bodyWithDocs(Object? body) => {
  ...body! as Map<String, Object?>,
  'nodes': [
    for (final node in (body as Map)['nodes'] as List<Object?>)
      switch (node) {
        {'kind': 'effect'} => {
          for (final MapEntry(:key, :value)
              in (node as Map<String, Object?>).entries)
            if (key != 'doc') key: value,
          'doc': node['doc'],
        },
        {'kind': 'copies'} => {
          ...node as Map<String, Object?>,
          'body': _bodyWithDocs(node['body']),
        },
        _ => node,
      },
  ],
};

/// The graph file the fixture [name] must give: its sources hashed as the
/// model hashes them, nothing built, the rest as given.
Future<Map<String, Object?>> expectedFile(
  String name, {
  required List<String> workflows,
  required Map<String, Object?> functions,
  List<Object?> warnings = const [],
}) async {
  final dir = fixture(name);
  final sources = await hashSources(dir, await packageSourcePaths(dir));
  return {
    'format': 3,
    'package': name,
    'fingerprint': fingerprintOf(sources),
    'sources': sources,
    'builds': <String, Object?>{},
    'workflows': workflows,
    'functions': withDocs(functions),
    'warnings': warnings,
  };
}

/// [actual] equals [expected], keys in the same order: the file is written
/// as it iterates.
void expectFile(Map<String, Object?> actual, Map<String, Object?> expected) {
  expect(actual, expected);
  expect(jsonEncode(actual), jsonEncode(expected));
}
