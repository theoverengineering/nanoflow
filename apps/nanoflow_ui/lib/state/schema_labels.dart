/// How the step details window names the types of a node's `in` and `out`
/// (docs/ui-spec.md «Окно деталей шага», README «Типы»): `#/Change` for a
/// type from `types`, a short description of any other schema, and the
/// fields of the type: `{ change, findings[] }`. Pure.
library;

import 'dart:convert';

/// The label of [schema]: the reference to a type from `types` as written
/// (`#/Change`), else a short description of it — `string`, `string[]`,
/// `string | null`, `enum`, `any`; `schema` when it says nothing shorter.
String typeLabel(Object? schema) {
  if (schema == true) return 'any';
  if (schema == false) return 'nothing';
  if (schema is! Map<String, Object?>) return 'schema';
  if (schema[r'$ref'] case final String ref) return ref;
  final type = schema['type'];
  if (type == 'array') {
    final items = schema['items'];
    return items == null ? 'array' : '${typeLabel(items)}[]';
  }
  if (type is String) return type;
  if (type is List) return type.join(' | ');
  if (schema.containsKey('enum')) return 'enum';
  if (schema.containsKey('const')) return jsonEncode(schema['const']);
  if (schema['anyOf'] ?? schema['oneOf'] case final List<Object?> choices) {
    return choices.map(typeLabel).join(' | ');
  }
  if (schema['title'] case final String title) return title;
  return schema.isEmpty ? 'any' : 'schema';
}

/// The fields of [schema], with references read from [types]: the names of
/// its properties, `[]` after those that are arrays — `{ change, findings[] }`
/// — and for an array those of its items, then `[]`. `null` for a schema
/// without properties.
String? fieldSummary(Object? schema, Map<String, Object?> types) {
  final resolved = _resolve(schema, types);
  if (resolved == null) return null;
  if (resolved['properties'] case final Map<String, Object?> properties) {
    if (properties.isEmpty) return '{ }';
    final names = [
      for (final MapEntry(:key, :value) in properties.entries)
        _isArray(value, types) ? '$key[]' : key,
    ];
    return '{ ${names.join(', ')} }';
  }
  if (resolved['type'] == 'array') {
    final items = fieldSummary(resolved['items'], types);
    return items == null ? null : '$items[]';
  }
  return null;
}

bool _isArray(Object? schema, Map<String, Object?> types) =>
    _resolve(schema, types)?['type'] == 'array';

/// [schema] with its references to `#/Name` followed into [types]; `null`
/// when it is not an object, or refers to no type, or round in a circle.
Map<String, Object?>? _resolve(Object? schema, Map<String, Object?> types) {
  final seen = <String>{};
  var current = schema;
  while (current is Map<String, Object?>) {
    final ref = current[r'$ref'];
    if (ref is! String) return current;
    if (!ref.startsWith('#/') || !seen.add(ref)) return null;
    current = types[ref.substring(2)];
  }
  return null;
}
