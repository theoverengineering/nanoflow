// Codecs (spec §4.4, decision D9): how the values a session keeps — the
// input of a workflow, its result and the result of each effect — become JSON,
// and come back from it as values of the types the code declares.
//
// A value becomes JSON through `jsonEncode`, which calls the `toJson` of a
// value that is not JSON itself; a value of an enum registered with
// `addEnum` is its name, and a record of two positional fields the list of
// them. It comes back by its type: the decoder of a type is found from the
// type alone, as a type is made of JSON types — `String`, `int`, `double`,
// `num`, `bool`, `Null`, `Object`, `Object?`, `List<…>` and
// `Map<String, …>` of them, `(…, …)` and `…?` — and of the types of the
// codecs registered with `addCodec` and `addEnum`. Dart does not take a type
// apart, but it tells whether one type is a subtype of another
// (`<A>[] is List<B>`), so the type is found by asking: is it a list, a map,
// a record, nullable, this or that leaf? One codec of `Report` so gives
// `Report?`, `List<Report>`, `Map<String, Report>` and any nesting of them,
// and `List<List<String>>` comes back as a `List<List<String>>`, not as the
// `List<dynamic>` `jsonDecode` gives.
//
// The type a function returns is found the same way, by asking whether the
// function is a `FutureOr<X> Function(Never)` (graph design §8): only that
// way round, as a function's type is never on the right of `is`, so the
// narrowest type that fits is taken. That is how a graph's node, a function
// of one parameter, has its result journaled without its type written
// twice.

import 'dart:async';
import 'dart:convert';

import 'errors.dart';

/// The codecs of a flow: what turns the values of its sessions into JSON
/// and back.
final class Codecs {
  /// The codecs registered with [add] and [addEnum], the last one first.
  final _codecs = <_Codec<Object?>>[];

  /// The decoder of each type asked for so far; `null` for a type with none.
  final _decoders = <Type, _Decoder?>{};

  /// The decoder of the result of each function asked for so far.
  final _results = <Function, _Decoder>{};

  /// Registers [fromJson], which makes a [T] of the JSON its `toJson` gave.
  void add<T>(T Function(Map<String, Object?> json) fromJson) =>
      _register(_Codec<T>.ofJson(fromJson));

  /// Registers the enum whose values are [values]: a value is written as its
  /// name, and read back by it.
  void addEnum<T extends Enum>(List<T> values) =>
      _register(_Codec<T>.ofEnum(values));

  void _register(_Codec<Object?> codec) {
    _codecs.insert(0, codec);
    _decoders.clear();
    _results.clear();
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
  Object? encode<T>(Object? value) => of<T>().encode(value);

  /// The [T] that [json], as [encode] gave it, stands for.
  ///
  /// Throws a [CodecException] naming [T] when [T] has no decoder, or [json]
  /// does not decode to a [T].
  T decode<T>(Object? json) => of<T>().decode(json) as T;

  /// Whether [T] has a decoder: it is a JSON type, or made of JSON types and
  /// types a codec has been registered for.
  bool canDecode<T>() => _decoderOf<T>() != null;

  /// How values declared as [T] become JSON and come back.
  TypeCodec of<T>() => TypeCodec._(this, _decoderOf<T>(), T, (v) => v is T);

  /// How what [node], a function of one parameter, returns becomes JSON and
  /// comes back: as the narrowest type made of JSON types and types with a
  /// codec that the function's result is one of — `Shape` for a function that
  /// returns a `Future<Shape>`, the codec of `Shape` for one that returns a
  /// `Future<Circle>` when `Circle` has none —, or, when there is none, as
  /// JSON as it is.
  TypeCodec resultOf(Function node) {
    final decoder = _results[node] ??= () {
      // A `Future` is an `Object` itself, so a function that returns one is
      // asked about the future's value: `FutureOr<Object>` would take any
      // future, of a nullable value too.
      final bool Function(_TypeOf<Object?> type) returns =
          node is Future<Object?> Function(Never)
          ? (type) => type.pass(<T>() => node is Future<T> Function(Never))
          : (type) => type.pass(<T>() => node is FutureOr<T> Function(Never));
      return _fitting(returns, (hole) => hole, 0) ?? _raw;
    }();
    return TypeCodec._(
      this,
      decoder,
      decoder.type.pass(<T>() => T),
      (_) => true,
    );
  }

  /// [value] as JSON, checked to come back through [decoder] as a [type],
  /// one that [isType] takes.
  Object? _encodeWith(
    _Decoder? decoder,
    Type type,
    bool Function(Object? value) isType,
    Object? value,
  ) {
    var native = true;
    final String text;
    try {
      text = jsonEncode(
        value,
        toEncodable: (object) {
          native = false;
          return _toEncodable(object);
        },
      );
    } on JsonUnsupportedObjectError catch (e) {
      throw CodecException(type, _unsupported(e));
    }
    final json = jsonDecode(text);
    if (decoder == null) throw CodecException(type, _noCodec);
    if (!native && !decoder.usesCodec) {
      throw CodecException(
        type,
        'a ${value.runtimeType} is JSON only through its toJson, and $type '
        'has no codec that reads it back: declare the type whose codec does',
      );
    }
    _decodeWith(decoder, type, isType, json);
    return json;
  }

  /// What [json] stands for, through [decoder], as a [type] that [isType]
  /// takes.
  Object? _decodeWith(
    _Decoder? decoder,
    Type type,
    bool Function(Object? value) isType,
    Object? json,
  ) {
    if (decoder == null) throw CodecException(type, _noCodec);
    final Object? value;
    try {
      value = decoder.decode(json);
    } catch (e) {
      throw CodecException(type, 'the JSON does not decode: $e');
    }
    if (!isType(value)) {
      throw CodecException(
        type,
        'the JSON decodes to a ${value.runtimeType}, which is not one',
      );
    }
    return value;
  }

  /// What `jsonEncode` writes for [object], which is not JSON itself: the
  /// name of a value of an enum with a codec, the fields of a record of two,
  /// or what its `toJson` gives.
  Object? _toEncodable(Object? object) {
    if (object is Enum) {
      for (final codec in _codecs) {
        if (codec.nameOf(object) case final name?) return name;
      }
    }
    if (object case (final a, final b)) return [a, b];
    return (object as dynamic).toJson();
  }

  _Decoder? _decoderOf<T>() => _decoders.putIfAbsent(
    T,
    () => _find(_TypeOf<T>(), (hole) => hole, (hole) => hole, 0),
  );

  /// The decoder of the part of [target] at the hole of the context: the
  /// type that, put in the hole, makes the context [target]; `null` when
  /// there is none.
  ///
  /// The context is made of `List<…>`, `Map<String, …>`, `…?` and the
  /// fields of records, around one hole, as `List<Map<String, _>>`; [depth]
  /// is how many of them. [upper] is it with the other field of each record
  /// as wide as can be, `Object?`, and [lower] with it as narrow, `Never`:
  /// what is put in the hole fits when [target] is a subtype of [upper] with
  /// it, and is the part when [lower] with it is a subtype of [target] too.
  _Decoder? _find(
    _TypeOf<Object?> target,
    _TypeOf<Object?> Function(_TypeOf<Object?> hole) upper,
    _TypeOf<Object?> Function(_TypeOf<Object?> hole) lower,
    int depth,
  ) {
    // The hole is at most [hole].
    bool fits(_TypeOf<Object?> hole) => target.isSubtypeOf(upper(hole));
    // The hole is [hole].
    bool equals(_TypeOf<Object?> hole) =>
        fits(hole) && lower(hole).isSubtypeOf(target);
    _Decoder? inner(_TypeOf<Object?> Function(_TypeOf<Object?> hole) around) =>
        _find(
          target,
          (hole) => upper(around(hole)),
          (hole) => lower(around(hole)),
          depth + 1,
        );

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
      final value = inner((hole) => hole.nullable);
      return value == null ? null : _nullableOf(value);
    }
    for (final type in _leaves) {
      if (equals(type)) return (type: type, decode: _same, usesCodec: false);
    }
    if (fits(const _TypeOf<List<Object?>>())) {
      final element = inner((hole) => hole.list);
      return element == null ? null : _listOf(element);
    }
    if (fits(const _TypeOf<Map<String, Object?>>())) {
      final value = inner((hole) => hole.map);
      return value == null ? null : _mapOf(value);
    }
    if (fits(const _TypeOf<(Object?, Object?)>())) {
      final first = _find(
        target,
        (hole) => upper(_pair(hole, const _TypeOf<Object?>())),
        (hole) => lower(_pair(hole, const _TypeOf<Never>())),
        depth + 1,
      );
      if (first == null) return null;
      final second = inner((hole) => _pair(first.type, hole));
      return second == null ? null : _pairOf(first, second);
    }
    return null;
  }

  /// The decoder of the narrowest type made of JSON types and types with a
  /// codec that [returns] says a function's result is a subtype of, put in
  /// the hole of [context]; `null` when there is none narrower than
  /// `Object?`.
  _Decoder? _fitting(
    bool Function(_TypeOf<Object?> type) returns,
    _TypeOf<Object?> Function(_TypeOf<Object?> hole) context,
    int depth,
  ) {
    bool fits(_TypeOf<Object?> hole) => returns(context(hole));
    _Decoder? inner(_TypeOf<Object?> Function(_TypeOf<Object?> hole) around) =>
        _fitting(returns, (hole) => context(around(hole)), depth + 1);

    if (depth > _maxDepth || fits(const _TypeOf<Never>())) return null;
    if (!fits(const _TypeOf<Object>())) {
      if (fits(const _TypeOf<Null>())) {
        return (type: const _TypeOf<Null>(), decode: _same, usesCodec: false);
      }
      final value = inner((hole) => hole.nullable);
      return value == null ? null : _nullableOf(value);
    }
    _Codec<Object?>? narrowest;
    for (final codec in _codecs) {
      if (fits(codec.type) &&
          (narrowest == null || codec.type.isSubtypeOf(narrowest.type))) {
        narrowest = codec;
      }
    }
    if (narrowest != null) {
      return (type: narrowest.type, decode: narrowest.decode, usesCodec: true);
    }
    for (final type in _leaves.skip(1)) {
      if (fits(type)) return (type: type, decode: _same, usesCodec: false);
    }
    if (fits(const _TypeOf<List<Object?>>())) {
      return _listOf(inner((hole) => hole.list) ?? _raw);
    }
    if (fits(const _TypeOf<Map<String, Object?>>())) {
      return _mapOf(inner((hole) => hole.map) ?? _raw);
    }
    if (fits(const _TypeOf<(Object?, Object?)>())) {
      final first =
          inner((hole) => _pair(hole, const _TypeOf<Object?>())) ?? _raw;
      final second = inner((hole) => _pair(first.type, hole)) ?? _raw;
      return _pairOf(first, second);
    }
    return (type: const _TypeOf<Object>(), decode: _same, usesCodec: false);
  }
}

/// How the values of one type become JSON and come back: the type a
/// workflow or an effect declares ([Codecs.of]), or the one a function
/// returns ([Codecs.resultOf]).
final class TypeCodec {
  TypeCodec._(this._codecs, this._decoder, this.type, this._isType);

  final Codecs _codecs;
  final _Decoder? _decoder;
  final bool Function(Object? value) _isType;

  /// The type, which the [CodecException]s name.
  final Type type;

  /// Whether [type] has a decoder.
  bool get canDecode => _decoder != null;

  /// [value] as JSON; see [Codecs.encode].
  Object? encode(Object? value) =>
      _codecs._encodeWith(_decoder, type, _isType, value);

  /// What [json] stands for; see [Codecs.decode].
  Object? decode(Object? json) =>
      _codecs._decodeWith(_decoder, type, _isType, json);
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

/// JSON as it is, as `Object?`.
const _Decoder _raw = (
  type: _TypeOf<Object?>(),
  decode: _same,
  usesCodec: false,
);

/// Why a type has no decoder.
const _noCodec =
    'it is neither a JSON type nor made of types with a codec: register '
    'their fromJson with addCodec, or their values with addEnum';

/// How a type comes back from JSON: the type, its decoder, and whether the
/// decoder calls a codec's `fromJson` or reads more than JSON as it is.
typedef _Decoder = ({
  _TypeOf<Object?> type,
  Object? Function(Object? json) decode,
  bool usesCodec,
});

_Decoder _nullableOf(_Decoder value) => (
  type: value.type.nullable,
  decode: (json) => json == null ? null : value.decode(json),
  usesCodec: value.usesCodec,
);

_Decoder _listOf(_Decoder element) => (
  type: element.type.list,
  decode: (json) => element.type.pass(
    <E>() => <E>[
      for (final item in json! as List<Object?>) element.decode(item) as E,
    ],
  ),
  usesCodec: element.usesCodec,
);

_Decoder _mapOf(_Decoder value) => (
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

/// A record of two is written as a list, so it always reads more than JSON.
_Decoder _pairOf(_Decoder first, _Decoder second) => (
  type: _pair(first.type, second.type),
  decode: (json) {
    final [a, b] = json! as List<Object?>;
    return (first.decode(a), second.decode(b));
  },
  usesCodec: true,
);

/// `(A, B)` for [a] of `A` and [b] of `B`.
_TypeOf<Object?> _pair(_TypeOf<Object?> a, _TypeOf<Object?> b) =>
    a.pass(<A>() => b.pass(<B>() => _TypeOf<(A, B)>()));

/// A codec registered with [Codecs.add] or [Codecs.addEnum].
final class _Codec<T> {
  _Codec.ofJson(T Function(Map<String, Object?> json) fromJson)
    : decode = ((json) => fromJson(json! as Map<String, Object?>)),
      _values = null;

  _Codec.ofEnum(List<T> values)
    : decode = ((json) => values.firstWhere(
        (value) => (value! as Enum).name == json,
        orElse: () => throw FormatException('no value is named $json'),
      )),
      _values = values;

  final Object? Function(Object? json) decode;

  /// The values of an enum; `null` for a codec of `fromJson`.
  final List<T>? _values;

  _TypeOf<T> get type => _TypeOf<T>();

  /// The name an enum's codec writes [value] as; `null` when [value] is not
  /// one of its values.
  String? nameOf(Enum value) =>
      _values?.contains(value) ?? false ? value.name : null;
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
    (final Enum value, _) =>
      'a ${value.runtimeType} is an enum without a codec: register its '
          'values with addEnum',
    (final object, final NoSuchMethodError cause)
        when '$cause'.contains("'toJson'") =>
      'a ${object.runtimeType} has no toJson',
    (final object, final cause?) =>
      'the toJson of a ${object.runtimeType} failed: $cause',
    (final object, null) => 'a ${object.runtimeType} is not JSON',
  };
}
