// Readers for the fields of a model's JSON form. Shared by the entities, the
// events and the changes; not part of the package's public API.
//
// Every reader throws a `FormatException` whose message starts with the key of
// the field, so a model that reads a model inside it can put its own key in
// front with [inside].

import 'time.dart';

/// The value of [key] in [json], which may be `null`.
///
/// A model always has all its fields, so a missing key is a problem even when
/// `null` would have been fine.
Object? readValue(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) throw FormatException('$key: missing');
  return json[key];
}

/// The string at [key].
String readString(Map<String, Object?> json, String key) {
  final value = readValue(json, key);
  if (value is String) return value;
  throw FormatException('$key: expected a string');
}

/// The string at [key], or `null`.
String? readStringOrNull(Map<String, Object?> json, String key) {
  final value = readValue(json, key);
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('$key: expected a string or null');
}

/// The integer at [key].
int readInt(Map<String, Object?> json, String key) {
  final value = readValue(json, key);
  if (value is int) return value;
  throw FormatException('$key: expected an integer');
}

/// [value] as an object, or `null` when it is not a map with string keys.
///
/// Also takes a `Map<dynamic, dynamic>` with string keys, which is what an
/// empty map literal inside another map literal is.
Map<String, Object?>? asObject(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map && value.keys.every((k) => k is String)) {
    return value.cast<String, Object?>();
  }
  return null;
}

/// The object at [key].
Map<String, Object?> readObject(Map<String, Object?> json, String key) =>
    asObject(readValue(json, key)) ??
    (throw FormatException('$key: expected an object'));

/// The list at [key].
List<Object?> readList(Map<String, Object?> json, String key) {
  final value = readValue(json, key);
  if (value is List<Object?>) return value;
  throw FormatException('$key: expected a list');
}

/// The strings in the list at [key]. A bad item is reported as `key[0]`.
List<String> readStrings(Map<String, Object?> json, String key) {
  final list = readList(json, key);
  return List.unmodifiable([
    for (var i = 0; i < list.length; i++)
      list[i] is String
          ? list[i] as String
          : throw FormatException('$key[$i]: expected a string'),
  ]);
}

/// The strings in the object at [key], by their keys. A bad value is reported
/// as `key.name`.
Map<String, String> readStringMap(Map<String, Object?> json, String key) {
  final object = readObject(json, key);
  return Map.unmodifiable({
    for (final MapEntry(key: name, :value) in object.entries)
      name: value is String
          ? value
          : throw FormatException('$key.$name: expected a string'),
  });
}

/// The objects in the list at [key], each made by [read]. A problem in the
/// third one is reported as `key[2].…`.
List<T> readObjects<T>(
  Map<String, Object?> json,
  String key,
  T Function(Map<String, Object?> item) read,
) {
  final list = readList(json, key);
  final items = <T>[];
  for (var i = 0; i < list.length; i++) {
    final item = asObject(list[i]);
    if (item == null) throw FormatException('$key[$i]: expected an object');
    items.add(inside('$key[$i]', () => read(item)));
  }
  return List.unmodifiable(items);
}

/// The objects in the object at [key], by their keys, each made by [read]
/// from its key and its fields. A problem in `a` is reported as `key.a.…`.
Map<String, T> readObjectMap<T>(
  Map<String, Object?> json,
  String key,
  T Function(String name, Map<String, Object?> item) read,
) {
  final object = readObject(json, key);
  final items = <String, T>{};
  for (final MapEntry(key: name, :value) in object.entries) {
    final item = asObject(value);
    if (item == null) throw FormatException('$key.$name: expected an object');
    items[name] = inside('$key.$name', () => read(name, item));
  }
  return Map.unmodifiable(items);
}

/// The object at [key], made by [read]. A problem in it is reported as
/// `key.…`.
T readNested<T>(
  Map<String, Object?> json,
  String key,
  T Function(Map<String, Object?> object) read,
) {
  final object = readObject(json, key);
  return inside(key, () => read(object));
}

/// The time at [key], written as `2026-09-20T14:03:11.470Z`.
DateTime readTime(Map<String, Object?> json, String key) {
  final text = readString(json, key);
  try {
    return parseTime(text);
  } on FormatException {
    throw FormatException(
      '$key: expected a UTC time like 2026-09-20T14:03:11.470Z',
    );
  }
}

/// Runs [read] and puts [place] in front of the place of a problem it finds:
/// `session` and `id: missing` become `session.id: missing`.
T inside<T>(String place, T Function() read) {
  try {
    return read();
  } on FormatException catch (e) {
    throw FormatException('$place.${e.message}');
  }
}
