// What the tests of describe share: the fixture packages and the graphs each
// must give.

import 'dart:convert';

import 'package:nanoflow_describe/nanoflow_describe.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A fixture package under `test/fixtures/`: `lib/`, `bin/`, no pubspec.
String fixture(String name) => p.join('test', 'fixtures', name);

/// The graphs and the warnings of the fixture [name], whose package is
/// called [name], as `functions` and `warnings` of a graph file have them.
Future<Map<String, Object?>> describeFixture(String name) async {
  final result = await describePackage(fixture(name), packageName: name);
  expect(result.errors, isEmpty);
  return {
    'functions': {
      for (final MapEntry(:key, :value) in result.graphs.entries)
        key: value.toJson(),
    },
    'warnings': [for (final warning in result.warnings) warning.toJson()],
  };
}

/// [functions] as the file has them: `doc: null` on a graph and on an effect
/// whose expectation gives none, in the place the file has it — the fixtures
/// document only what their tests say.
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
        _ => node,
      },
  ],
};

/// The graphs and the warnings a fixture must give ([describeFixture]).
Map<String, Object?> expectedGraphs({
  required Map<String, Object?> functions,
  List<Object?> warnings = const [],
}) => {'functions': withDocs(functions), 'warnings': warnings};

/// [actual] equals [expected], keys in the same order: the file is written
/// as it iterates.
void expectFile(Map<String, Object?> actual, Map<String, Object?> expected) {
  expect(actual, expected);
  expect(jsonEncode(actual), jsonEncode(expected));
}
