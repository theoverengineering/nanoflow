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
