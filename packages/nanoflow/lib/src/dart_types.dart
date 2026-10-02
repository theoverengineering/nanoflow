import 'dart:mirrors';

/// A Dart type that cannot be data between nodes: it has no JSON form.
final class UnsupportedTypeException implements Exception {
  UnsupportedTypeException._(this._type, this.message);

  final TypeMirror _type;

  /// What is wrong, naming the type: `Set<int> is not a JSON type`.
  final String message;

  @override
  String toString() => 'UnsupportedTypeException: $message';
}

/// The JSON Schema of the data of [type], or `null` when [type] carries no
/// data: `void`, `dynamic`, `Null`, `Object` and `Object?`.
///
/// `String` is `{"type": "string"}`, `int` is `{"type": "integer"}`,
/// `double` and `num` are `{"type": "number"}`, `bool` is
/// `{"type": "boolean"}`, `List<T>` is an array of `T`, `Map<String, T>` an
/// object of `T`. An enum or a class with a `fromJson` constructor and a
/// `toJson` method is a reference `#/Name`; its entry is added to [types]:
/// the enum's names, or the class's title.
///
/// Throws an [UnsupportedTypeException] for any other type.
Map<String, Object?>? schemaOf(TypeMirror type, Map<String, Object?> types) {
  if (_kindOf(type) == _Kind.none) return null;
  try {
    return _schema(type, types);
  } on UnsupportedTypeException catch (e) {
    if (e._type == type) rethrow;
    throw UnsupportedTypeException._(type, '${_nameOf(type)}: ${e.message}');
  }
}

/// What is wrong with [type], which [schemaOf] takes, as the type of a
/// node's `in` or `out` when it comes to `null`; `null` when nothing is.
/// [nullable] tells whether [type] is nullable, which a mirror does not:
/// `Report?` and `Report` have the same one.
///
/// The data between nodes cannot be null: a data type must not be nullable,
/// nor may the items of its lists and the values of its maps. A type that
/// carries no data must be: `Object` is not `Object?`.
String? nullError(TypeMirror type, {required bool nullable}) {
  if (_kindOf(type) == _Kind.none) {
    return nullable
        ? null
        : '${_nameOf(type)} — use Object? for a node without in/out';
  }
  final (:name, :holdsNull) = _withNulls(type);
  if (!nullable && !holdsNull) return null;
  return '$name${nullable ? '?' : ''} — data cannot be null; use a class or '
      'Object? for a node without in/out';
}

/// What a function returning [type] gives once awaited: [type] without
/// `Future` and `FutureOr`.
TypeMirror awaited(TypeMirror type) {
  var result = type;
  while (result is ClassMirror &&
      (result.originalDeclaration.qualifiedName == #dart.async.Future ||
          result.originalDeclaration.qualifiedName == #dart.async.FutureOr)) {
    result = result.typeArguments.single;
  }
  return result;
}

/// The value of [type] that [json], a decoded JSON value, stands for.
///
/// A class is built by its `fromJson` constructor from [json] as it is, an
/// enum value is found by name, a JSON integer is taken as a `double`. Lists
/// and maps are built with the declared item type. For a type that carries
/// no data, [json] is returned as it is.
///
/// Throws a [FormatException] when [json] does not fit [type]; its message
/// starts with the place inside [json], such as `[1]: expected an integer`.
/// Throws an [UnsupportedTypeException] for a type [schemaOf] rejects.
Object? decodeAs(Type type, Object? json) =>
    _decode(reflectType(type), json, '');

/// [value] as JSON: lists, maps with `String` keys, strings, numbers,
/// booleans and `null`.
///
/// An enum value is written by name; any other object by its `toJson()`,
/// whose result is encoded the same way.
///
/// Throws an [ArgumentError] for an object without `toJson()` or a map key
/// that is not a `String`.
Object? encodeValue(Object? value) => switch (value) {
  null || bool() || num() || String() => value,
  Enum() => value.name,
  List<Object?>() => [for (final item in value) encodeValue(item)],
  Map<Object?, Object?>() => {
    for (final MapEntry(:key, :value) in value.entries)
      _stringKey(key): encodeValue(value),
  },
  _ => encodeValue(_toJson(value)),
};

enum _Kind {
  none,
  string,
  integer,
  number,
  boolean,
  list,
  map,
  enumeration,
  object,
}

final ClassMirror _object = reflectClass(Object);
final ClassMirror _null = reflectClass(Null);
final ClassMirror _string = reflectClass(String);
final ClassMirror _int = reflectClass(int);
final ClassMirror _double = reflectClass(double);
final ClassMirror _num = reflectClass(num);
final ClassMirror _bool = reflectClass(bool);
final ClassMirror _list = reflectClass(List);
final ClassMirror _map = reflectClass(Map);

_Kind _kindOf(TypeMirror type) {
  final mirrors = currentMirrorSystem();
  if (type == mirrors.voidType ||
      type == mirrors.dynamicType ||
      type == _object ||
      type == _null) {
    return _Kind.none;
  }
  if (type is! ClassMirror || type is FunctionTypeMirror) {
    throw UnsupportedTypeException._(
      type,
      '${_nameOf(type)} is not a JSON type',
    );
  }
  if (type == _string) return _Kind.string;
  if (type == _int) return _Kind.integer;
  if (type == _double || type == _num) return _Kind.number;
  if (type == _bool) return _Kind.boolean;
  if (type.originalDeclaration == _list) return _Kind.list;
  if (type.originalDeclaration == _map) {
    if (type.typeArguments.first != _string) {
      throw UnsupportedTypeException._(
        type,
        '${_nameOf(type)} has keys that are not String',
      );
    }
    return _Kind.map;
  }
  if (type.isEnum) return _Kind.enumeration;
  if ((type.owner as LibraryMirror?)?.uri.isScheme('dart') ?? false) {
    throw UnsupportedTypeException._(
      type,
      '${_nameOf(type)} is not a JSON type',
    );
  }
  final hasFromJson = type.declarations.values.any(
    (d) =>
        d is MethodMirror && d.isConstructor && d.constructorName == #fromJson,
  );
  if (!hasFromJson || !_hasToJson(type)) {
    throw UnsupportedTypeException._(
      type,
      '${_nameOf(type)} needs a fromJson constructor and a toJson method',
    );
  }
  return _Kind.object;
}

/// Whether [type] has an instance method `toJson()`, abstract or not:
/// declared by the class itself or by a class it extends, mixes in or
/// implements.
///
/// `instanceMembers` leaves abstract methods out, such as the `toJson()` a
/// sealed base declares for its subclasses to implement, or the one freezed
/// declares in the mixin it generates. Encoding calls the `toJson()` of the
/// value's own class.
bool _hasToJson(ClassMirror type) {
  final declared = type.declarations[#toJson];
  if (declared != null) {
    return declared is MethodMirror &&
        declared.isRegularMethod &&
        !declared.isStatic;
  }
  return [
    ?type.superclass,
    if (type.mixin != type) type.mixin,
    ...type.superinterfaces,
  ].any(_hasToJson);
}

/// The schema of [type], which is [schemaOf]'s type or a part of it: there,
/// a type that carries no data has no JSON form either.
Map<String, Object?> _schema(TypeMirror type, Map<String, Object?> types) {
  final arguments = type.typeArguments;
  final name = _nameOf(type);
  return switch (_kindOf(type)) {
    _Kind.none => throw UnsupportedTypeException._(
      type,
      '$name is not a JSON type',
    ),
    _Kind.string => {'type': 'string'},
    _Kind.integer => {'type': 'integer'},
    _Kind.number => {'type': 'number'},
    _Kind.boolean => {'type': 'boolean'},
    _Kind.list => {'type': 'array', 'items': _schema(arguments[0], types)},
    _Kind.map => {
      'type': 'object',
      'additionalProperties': _schema(arguments[1], types),
    },
    _Kind.enumeration => _named(name, {'enum': _enumNames(type)}, types),
    _Kind.object => _named(name, {'title': name}, types),
  };
}

Map<String, Object?> _named(
  String name,
  Map<String, Object?> entry,
  Map<String, Object?> types,
) {
  types.putIfAbsent(name, () => entry);
  return {r'$ref': '#/$name'};
}

Object? _decode(TypeMirror type, Object? json, String place) {
  FormatException wrong(String expected) =>
      FormatException(_at(place, 'expected $expected'));

  switch (_kindOf(type)) {
    case _Kind.none:
      return json;
    case _Kind.string:
      return json is String ? json : throw wrong('a string');
    case _Kind.integer:
      return json is int ? json : throw wrong('an integer');
    case _Kind.number:
      if (json is! num) throw wrong('a number');
      return type == _double ? json.toDouble() : json;
    case _Kind.boolean:
      return json is bool ? json : throw wrong('a boolean');
    case _Kind.list:
      if (json is! List<Object?>) throw wrong('an array');
      final itemType = type.typeArguments[0];
      final items = [
        for (var i = 0; i < json.length; i++)
          _decode(itemType, json[i], '$place[$i]'),
      ];
      return (type as ClassMirror).newInstance(#from, [items]).reflectee;
    case _Kind.map:
      if (json is! Map<String, Object?>) throw wrong('an object');
      final valueType = type.typeArguments[1];
      final entries = {
        for (final MapEntry(:key, :value) in json.entries)
          key: _decode(valueType, value, place.isEmpty ? key : '$place.$key'),
      };
      return (type as ClassMirror).newInstance(#from, [entries]).reflectee;
    case _Kind.enumeration:
      for (final value in _enumValues(type)) {
        if (value.name == json) return value;
      }
      throw wrong('one of ${_enumNames(type).join(', ')}');
    case _Kind.object:
      try {
        return (type as ClassMirror).newInstance(#fromJson, [json]).reflectee;
      } catch (e) {
        throw FormatException(
          _at(place, '${_nameOf(type)}.fromJson failed: $e'),
        );
      }
  }
}

/// [type] named as Dart writes it, with `?` on the items of its lists and
/// the values of its maps that may be null — a mirror leaves `?` out — and
/// whether any may.
({String name, bool holdsNull}) _withNulls(TypeMirror type) {
  final kind = _kindOf(type);
  if (kind != _Kind.list && kind != _Kind.map) {
    return (name: _nameOf(type), holdsNull: false);
  }
  final item = _withNulls(type.typeArguments.last);
  final takesNull = _itemsTakeNull(type as ClassMirror, kind);
  final itemName = takesNull ? '${item.name}?' : item.name;
  return (
    name: kind == _Kind.list ? 'List<$itemName>' : 'Map<String, $itemName>',
    holdsNull: takesNull || item.holdsNull,
  );
}

/// Whether a list or a map of [type] takes a `null` item: an empty one is
/// made and given one.
bool _itemsTakeNull(ClassMirror type, _Kind kind) {
  final list = kind == _Kind.list;
  final empty = type.newInstance(#from, [
    if (list) <Object?>[] else <String, Object?>{},
  ]);
  try {
    list ? empty.invoke(#add, [null]) : empty.invoke(#[]=, ['', null]);
    return true;
  } on TypeError {
    return false;
  }
}

String _stringKey(Object? key) => key is String
    ? key
    : throw ArgumentError.value(key, 'key', 'is not a String');

String _at(String place, String message) =>
    place.isEmpty ? message : '$place: $message';

List<Enum> _enumValues(TypeMirror type) =>
    ((type as ClassMirror).getField(#values).reflectee as List<Object?>)
        .cast<Enum>();

List<String> _enumNames(TypeMirror type) => [
  for (final value in _enumValues(type)) value.name,
];

Object? _toJson(Object value) {
  final mirror = reflect(value);
  if (!(mirror.type.instanceMembers[#toJson]?.isRegularMethod ?? false)) {
    throw ArgumentError.value(value, 'value', 'has no toJson method');
  }
  return mirror.invoke(#toJson, []).reflectee;
}

String _nameOf(TypeMirror type) {
  final name = MirrorSystem.getName(type.simpleName);
  final arguments = type.typeArguments;
  return arguments.isEmpty
      ? name
      : '$name<${arguments.map(_nameOf).join(', ')}>';
}
