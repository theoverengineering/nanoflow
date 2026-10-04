/// Data as the effect details window shows it (docs/ui-spec.md «Окно деталей
/// эффекта»: «Данные»): `Schema` — fields with their type and value, nested
/// objects and arrays opened and closed; `JSON` — the text, its parts told
/// apart for highlighting. Pure.
library;

import 'dart:convert';

import 'texts.dart';

/// A row of the `Schema` view: a field, an item, or the value itself.
final class SchemaRow {
  const SchemaRow._({
    required this.path,
    required this.depth,
    required this.name,
    required this.type,
    required this.text,
    required this.open,
  });

  /// Where the value is in the data, as a JSON Pointer: `/change/id`.
  final String path;

  /// How deep it is nested: 0 for a field of the data.
  final int depth;

  /// The field's key, the item's index, or `value` for data that is neither
  /// an object nor an array.
  final String name;

  /// The JSON type: `string`, `number`, `boolean`, `null`, `object`,
  /// `array`.
  final String type;

  /// The value on one line; for an object or an array, its size: `2 fields`,
  /// `3 items`.
  final String text;

  /// Whether an object's or an array's rows follow it.
  final bool open;

  bool get container => type == 'object' || type == 'array';
}

/// The rows of the `Schema` view of [value]: the fields of an object, the
/// items of an array, else the value itself. An object or an array nested
/// less than [openDepth] deep is open, one deeper closed; the [toggled]
/// paths are the other way round.
List<SchemaRow> schemaRows(
  Object? value, {
  Set<String> toggled = const {},
  int openDepth = 1,
}) {
  final rows = <SchemaRow>[];
  void add(String path, int depth, String name, Object? value) {
    final open = (depth < openDepth) != toggled.contains(path);
    switch (value) {
      case Map<String, Object?>():
        rows.add(
          SchemaRow._(
            path: path,
            depth: depth,
            name: name,
            type: 'object',
            text: count(value.length, 'field'),
            open: open,
          ),
        );
        if (open) {
          for (final MapEntry(:key, value: field) in value.entries) {
            add('$path/${_escape(key)}', depth + 1, key, field);
          }
        }
      case List<Object?>():
        rows.add(
          SchemaRow._(
            path: path,
            depth: depth,
            name: name,
            type: 'array',
            text: count(value.length, 'item'),
            open: open,
          ),
        );
        if (open) {
          for (final (i, item) in value.indexed) {
            add('$path/$i', depth + 1, '$i', item);
          }
        }
      default:
        rows.add(
          SchemaRow._(
            path: path,
            depth: depth,
            name: name,
            type: _typeOf(value),
            text: _textOf(value),
            open: false,
          ),
        );
    }
  }

  switch (value) {
    case Map<String, Object?>():
      for (final MapEntry(:key, :value) in value.entries) {
        add('/${_escape(key)}', 0, key, value);
      }
    case List<Object?>():
      for (final (i, item) in value.indexed) {
        add('/$i', 0, '$i', item);
      }
    default:
      add('', 0, 'value', value);
  }
  return rows;
}

/// [key] as a JSON Pointer writes it.
String _escape(String key) => key.replaceAll('~', '~0').replaceAll('/', '~1');

String _typeOf(Object? value) => switch (value) {
  String() => 'string',
  num() => 'number',
  bool() => 'boolean',
  _ => 'null',
};

/// A string without its quotes, its line breaks and such escaped as in JSON;
/// `""` for the empty one.
String _textOf(Object? value) {
  if (value is! String) return jsonEncode(value);
  if (value.isEmpty) return '""';
  final json = jsonEncode(value);
  return json.substring(1, json.length - 1);
}

/// The lines of the `JSON` view of [value]: indented by two spaces.
List<String> jsonLines(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(value).split('\n');

/// A part of a line of JSON, for highlighting.
enum JsonPart { key, string, number, literal, punctuation, space }

typedef JsonToken = ({JsonPart part, String text});

/// The parts of [line], a line of [jsonLines] or the start of one: keys,
/// strings, numbers, `true`, `false` and `null`, punctuation, spaces. A
/// string the line cuts off runs to its end.
List<JsonToken> jsonTokens(String line) {
  final tokens = <JsonToken>[];
  var i = 0;
  while (i < line.length) {
    final start = i;
    final char = line[i];
    final JsonPart part;
    if (char == '"') {
      i++;
      while (i < line.length && line[i] != '"') {
        i += line[i] == r'\' ? 2 : 1;
      }
      i = i < line.length ? i + 1 : line.length;
      part = _isKey(line, i) ? JsonPart.key : JsonPart.string;
    } else if (char == ' ') {
      while (i < line.length && line[i] == ' ') {
        i++;
      }
      part = JsonPart.space;
    } else if ('{}[],:'.contains(char)) {
      i++;
      part = JsonPart.punctuation;
    } else {
      while (i < line.length && !' {}[],:"'.contains(line[i])) {
        i++;
      }
      part = '-0123456789'.contains(char) ? JsonPart.number : JsonPart.literal;
    }
    tokens.add((part: part, text: line.substring(start, i)));
  }
  return tokens;
}

/// Whether a colon follows [at] in [line], past spaces.
bool _isKey(String line, int at) {
  var i = at;
  while (i < line.length && line[i] == ' ') {
    i++;
  }
  return i < line.length && line[i] == ':';
}

/// How many bytes the JSON of [value] takes in UTF-8.
int byteSize(Object? value) => utf8.encode(jsonEncode(value)).length;

/// [bytes] as the window shows a size: `214 B`, `12,345 B`.
String sizeText(int bytes) => '${thousands(bytes)} B';
