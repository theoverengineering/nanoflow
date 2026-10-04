// Codecs (spec §4.4, decision D9): how the values a session keeps — the
// input of a workflow, its result and the result of each effect — become JSON,
// and come back from it as values of the types the code declares.
//
// A value becomes JSON through `jsonEncode`, which calls the `toJson` of a
// value that is not JSON itself. It comes back by its type: the decoder of a
// type is found from the type alone, as a type is made of JSON types —
// `String`, `int`, `double`, `num`, `bool`, `Null`, `Object`, `Object?`,
// `List<…>` and `Map<String, …>` of them, and `…?` — and of the types
// of the codecs registered with `addCodec`. Dart does not take a type apart,
// but it tells whether one type is a subtype of another
// (`<A>[] is List<B>`), so the type is found by asking: is it a list, a map,
// nullable, this or that leaf? One codec of `Report` so gives `Report?`,
// `List<Report>`, `Map<String, Report>` and any nesting of them, and
// `List<List<String>>` comes back as a `List<List<String>>`, not as the
// `List<dynamic>` `jsonDecode` gives.

import 'dart:convert';

import 'errors.dart';

/// The codecs of a flow: what turns the values of its sessions into JSON
/// and back.
final class Codecs {
  /// The codecs registered with [add], the last one first.
  final _codecs = <_Codec<Object?>>[];

  /// The decoder of each type asked for so far; `null` for a type with none.
  final _decoders = <Type, _Decoder?>{};

  /// Registers [fromJson], which makes a [T] of the JSON its `toJson` gave.
  void add<T>(T Function(Map<String, Object?> json) fromJson) {
    _codecs.insert(0, _Codec<T>(fromJson));
    _decoders.clear();
  }

  /// [value], declared as a [T], as JSON: lists, maps with `String` keys,
  /// strings, numbers, booleans and `null`.
  ///
  /// Checks that the JSON comes back as a [T]. Throws a [CodecException]
  /// naming [T] when it does not: when [value] is not JSON and has no
  /// `toJson`, or its `toJson` fails; when [T] is neither a JSON type nor a
  /// type a codec has been registered for; when a value that is JSON only
  /// through its `toJson` would come back as something else than it, as a
  /// `Report` declared as `Object?` would come back as a map; and when the
  /// codec's `fromJson` fails or does not give a [T].
  Object? encode<T>(Object? value) {
    var native = true;
    final String text;
    try {
      text = jsonEncode(
        value,
        toEncodable: (object) {
          native = false;
          return (object as dynamic).toJson();
        },
      );
    } on JsonUnsupportedObjectError catch (e) {
      throw CodecException(T, _unsupported(e));
    }
    final json = jsonDecode(text);
    final decoder = _decoderOf<T>() ?? (throw CodecException(T, _noCodec));
    if (!native && !decoder.usesCodec) {
      throw CodecException(
        T,
        'a ${value.runtimeType} is JSON only through its toJson, and $T has '
        'no codec that reads it back: declare the type whose codec does',
      );
    }
    decode<T>(json);
    return json;
  }

  /// The [T] that [json], as [encode] gave it, stands for.
  ///
  /// Throws a [CodecException] naming [T] when [T] has no decoder, or [json]
  /// does not decode to a [T].
  T decode<T>(Object? json) {
    final decoder = _decoderOf<T>() ?? (throw CodecException(T, _noCodec));
    final Object? value;
    try {
      value = decoder.decode(json);
    } catch (e) {
      throw CodecException(T, 'the JSON does not decode: $e');
    }
    if (value is! T) {
      throw CodecException(
        T,
        'the JSON decodes to a ${value.runtimeType}, which is not one',
      );
    }
    return value;
  }

  /// Whether [T] has a decoder: it is a JSON type, or made of JSON types and
  /// types a codec has been registered for.
  bool canDecode<T>() => _decoderOf<T>() != null;

  _Decoder? _decoderOf<T>() =>
      _decoders.putIfAbsent(T, () => _find(_TypeOf<T>(), (hole) => hole, 0));

  /// The decoder of the part of [target] at the hole of [context]: the type
  /// that, put in the hole, makes [context] [target]; `null` when there is
  /// none.
  ///
  /// [context] is made of `List<…>`, `Map<String, …>` and `…?`, around
  /// one hole, as `List<Map<String, _>>`; [depth] is how many of them.
  _Decoder? _find(
    _TypeOf<Object?> target,
    _TypeOf<Object?> Function(_TypeOf<Object?> hole) context,
    int depth,
  ) {
    // The hole is at most [hole].
    bool fits(_TypeOf<Object?> hole) => target.isSubtypeOf(context(hole));
    // The hole is [hole].
    bool equals(_TypeOf<Object?> hole) =>
        fits(hole) && context(hole).isSubtypeOf(target);

    if (depth > _maxDepth || fits(const _TypeOf<Never>())) return null;
    for (final codec in _codecs) {
      if (equals(codec.type)) {
        return (type: codec.type, decode: codec.decode, usesCodec: true);
      }
    }
    if (!fits(const _TypeOf<Object>())) {
      // The hole takes null.
      for (final type in const [_TypeOf<Object?>(), _TypeOf<Null>()]) {
        if (equals(type)) return (type: type, decode: _same, usesCodec: false);
      }
      final inner = _find(target, (hole) => context(hole.nullable), depth + 1);
      if (inner == null) return null;
      return (
        type: inner.type.nullable,
        decode: (json) => json == null ? null : inner.decode(json),
        usesCodec: inner.usesCodec,
      );
    }
    for (final type in _leaves) {
      if (equals(type)) return (type: type, decode: _same, usesCodec: false);
    }
    if (fits(const _TypeOf<List<Object?>>())) {
      final element = _find(target, (hole) => context(hole.list), depth + 1);
      if (element == null) return null;
      return (
        type: element.type.list,
        decode: (json) => element.type.pass(
          <E>() => <E>[
            for (final item in json! as List<Object?>)
              element.decode(item) as E,
          ],
        ),
        usesCodec: element.usesCodec,
      );
    }
    if (fits(const _TypeOf<Map<String, Object?>>())) {
      final value = _find(target, (hole) => context(hole.map), depth + 1);
      if (value == null) return null;
      return (
        type: value.type.map,
        decode: (json) => value.type.pass(
          <E>() => <String, E>{
            for (final MapEntry(:key, value: item)
                in (json! as Map<String, Object?>).entries)
              key: value.decode(item) as E,
          },
        ),
        usesCodec: value.usesCodec,
      );
    }
    return null;
  }
}

/// How deep [Codecs] looks into a type: deeper is taken for a type that is
/// not JSON.
const _maxDepth = 64;

/// The JSON types that are neither nullable nor lists or maps.
const _leaves = [
  _TypeOf<Object>(),
  _TypeOf<String>(),
  _TypeOf<bool>(),
  _TypeOf<int>(),
  _TypeOf<double>(),
  _TypeOf<num>(),
];

Object? _same(Object? json) => json;

/// Why a type has no decoder.
const _noCodec =
    'it is neither a JSON type nor made of types with a codec: register '
    'their fromJson with addCodec';

/// How a type comes back from JSON: the type, its decoder, and whether the
/// decoder calls a codec's `fromJson`.
typedef _Decoder = ({
  _TypeOf<Object?> type,
  Object? Function(Object? json) decode,
  bool usesCodec,
});

/// A codec registered with [Codecs.add].
final class _Codec<T> {
  _Codec(this.fromJson);

  final T Function(Map<String, Object?> json) fromJson;

  _TypeOf<T> get type => _TypeOf<T>();

  Object? decode(Object? json) => fromJson(json! as Map<String, Object?>);
}

/// The type [X], which it hands to generic code, and the types made of it.
final class _TypeOf<X> {
  const _TypeOf();

  /// What [f] gives for [X].
  R pass<R>(R Function<Y>() f) => f<X>();

  _TypeOf<X?> get nullable => _TypeOf<X?>();

  _TypeOf<List<X>> get list => _TypeOf<List<X>>();

  _TypeOf<Map<String, X>> get map => _TypeOf<Map<String, X>>();

  /// Whether [X] is a subtype of the type of [other].
  bool isSubtypeOf(_TypeOf<Object?> other) =>
      other.pass(<Y>() => <X>[] is List<Y>);
}

/// Why `jsonEncode` failed with [error]: what the value that is not JSON is,
/// deepest first.
String _unsupported(JsonUnsupportedObjectError error) {
  var e = error;
  for (
    var cause = e.cause;
    cause is JsonUnsupportedObjectError;
    cause = e.cause
  ) {
    e = cause;
  }
  if (e is JsonCyclicError) return 'a list or a map contains itself';
  return switch ((e.unsupportedObject, e.cause)) {
    (final num number, _) => '$number is not a JSON number',
    (Map(), _) => 'a map with keys that are not strings is not JSON',
    (final object, final NoSuchMethodError cause)
        when '$cause'.contains("'toJson'") =>
      'a ${object.runtimeType} has no toJson',
    (final object, final cause?) =>
      'the toJson of a ${object.runtimeType} failed: $cause',
    (final object, null) => 'a ${object.runtimeType} is not JSON',
  };
}
