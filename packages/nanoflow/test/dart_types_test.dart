import 'dart:async';
import 'dart:mirrors';

import 'package:nanoflow/src/dart_types.dart';
import 'package:test/test.dart';

enum Color { red, green }

class Point {
  Point(this.x, this.y);

  factory Point.fromJson(Map<String, Object?> json) =>
      Point(json['x'] as int, json['y'] as int);

  final int x;
  final int y;

  Map<String, Object?> toJson() => {'x': x, 'y': y};
}

/// Decoded by a named generative constructor; its toJson leaves the nested
/// points to be encoded.
class Segment {
  Segment.fromJson(Map<String, Object?> json)
    : from = Point.fromJson(json['from'] as Map<String, Object?>),
      to = Point.fromJson(json['to'] as Map<String, Object?>);

  final Point from;
  final Point to;

  Map<String, Object?> toJson() => {'from': from, 'to': to};
}

class Opaque {}

Type typeOf<T>() => T;

Map<String, Object?>? schema(Type type, [Map<String, Object?>? types]) =>
    schemaOf(reflectType(type), types ?? {});

Matcher formatError(String message) => throwsA(
  isA<FormatException>().having((e) => e.message, 'message', message),
);

void main() {
  group('schemaOf', () {
    test('maps JSON primitives', () {
      expect(schema(String), {'type': 'string'});
      expect(schema(int), {'type': 'integer'});
      expect(schema(double), {'type': 'number'});
      expect(schema(num), {'type': 'number'});
      expect(schema(bool), {'type': 'boolean'});
    });

    test('maps lists and maps with String keys', () {
      expect(schema(typeOf<List<String>>()), {
        'type': 'array',
        'items': {'type': 'string'},
      });
      expect(schema(typeOf<Map<String, List<int>>>()), {
        'type': 'object',
        'additionalProperties': {
          'type': 'array',
          'items': {'type': 'integer'},
        },
      });
    });

    test('refers to enums and classes, declared in types', () {
      final types = <String, Object?>{};
      expect(schema(Color, types), {r'$ref': '#/Color'});
      expect(schema(typeOf<List<Point>>(), types), {
        'type': 'array',
        'items': {r'$ref': '#/Point'},
      });
      expect(types, {
        'Color': {
          'enum': ['red', 'green'],
        },
        'Point': {'title': 'Point'},
      });
    });

    test('gives null for types that carry no data', () {
      final types = <String, Object?>{};
      for (final type in [
        typeOf<void>(),
        dynamic,
        Null,
        Object,
        typeOf<Object?>(),
      ]) {
        expect(schema(type, types), isNull, reason: '$type');
      }
      expect(types, isEmpty);
    });

    test('rejects types that are not JSON types', () {
      void rejects(Type type, String message) => expect(
        () => schema(type),
        throwsA(
          isA<UnsupportedTypeException>().having(
            (e) => e.message,
            'message',
            message,
          ),
        ),
      );
      rejects(typeOf<Set<int>>(), 'Set<int> is not a JSON type');
      rejects(DateTime, 'DateTime is not a JSON type');
      rejects(
        Opaque,
        'Opaque needs a fromJson constructor and a toJson method',
      );
      rejects(
        typeOf<Map<int, Point>>(),
        'Map<int, Point> has keys that are not String',
      );
      rejects(
        typeOf<List<Object?>>(),
        'List<Object>: Object is not a JSON type',
      );
      rejects(
        typeOf<Map<String, Set<int>>>(),
        'Map<String, Set<int>>: Set<int> is not a JSON type',
      );
    });
  });

  group('awaited', () {
    test('unwraps Future and FutureOr', () {
      expect(awaited(reflectType(typeOf<Future<Point>>())), reflectType(Point));
      expect(awaited(reflectType(typeOf<FutureOr<int>>())), reflectType(int));
      expect(
        awaited(reflectType(typeOf<Future<void>>())),
        currentMirrorSystem().voidType,
      );
      expect(awaited(reflectType(String)), reflectType(String));
    });
  });

  group('decodeAs', () {
    test('builds a class with its fromJson factory', () {
      final point = decodeAs(Point, {'x': 1, 'y': 2})! as Point;
      expect((point.x, point.y), (1, 2));
    });

    test('builds a class with its fromJson named constructor', () {
      final segment =
          decodeAs(Segment, {
                'from': {'x': 1, 'y': 2},
                'to': {'x': 3, 'y': 4},
              })!
              as Segment;
      expect(segment.to.y, 4);
    });

    test('builds a list of the declared item type', () {
      final points = decodeAs(typeOf<List<Point>>(), [
        {'x': 1, 'y': 2},
      ]);
      expect(points, isA<List<Point>>().having((l) => l.single.y, 'y', 2));
    });

    test('builds a map of the declared value type', () {
      final counts = decodeAs(typeOf<Map<String, int>>(), {'a': 1, 'b': 2});
      expect(counts, isA<Map<String, int>>());
      expect(counts, {'a': 1, 'b': 2});
    });

    test('takes an enum by name', () {
      expect(decodeAs(Color, 'green'), Color.green);
    });

    test('takes a JSON integer as a double', () {
      expect(decodeAs(double, 3), isA<double>().having((d) => d, 'value', 3.0));
    });

    test('takes primitives as they are', () {
      expect(decodeAs(String, 'x'), 'x');
      expect(decodeAs(int, 7), 7);
      expect(decodeAs(num, 7.5), 7.5);
      expect(decodeAs(bool, false), false);
    });

    test('passes anything through for types that carry no data', () {
      expect(decodeAs(typeOf<Object?>(), {'a': 1}), {'a': 1});
      expect(decodeAs(dynamic, null), isNull);
    });

    test('throws a FormatException with the place for a wrong shape', () {
      expect(() => decodeAs(String, 1), formatError('expected a string'));
      expect(() => decodeAs(int, 1.5), formatError('expected an integer'));
      expect(() => decodeAs(double, '1'), formatError('expected a number'));
      expect(() => decodeAs(bool, 'true'), formatError('expected a boolean'));
      expect(
        () => decodeAs(typeOf<List<int>>(), {'a': 1}),
        formatError('expected an array'),
      );
      expect(
        () => decodeAs(typeOf<List<int>>(), [1, 'x']),
        formatError('[1]: expected an integer'),
      );
      expect(
        () => decodeAs(typeOf<Map<String, List<int>>>(), {
          'a': [1, null],
        }),
        formatError('a[1]: expected an integer'),
      );
      expect(
        () => decodeAs(typeOf<Map<String, int>>(), [1]),
        formatError('expected an object'),
      );
      expect(
        () => decodeAs(Color, 'blue'),
        formatError('expected one of red, green'),
      );
      expect(
        () => decodeAs(typeOf<List<Point>>(), ['x']),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            startsWith('[0]: Point.fromJson failed: '),
          ),
        ),
      );
    });
  });

  group('encodeValue', () {
    test('keeps primitives and null', () {
      expect(encodeValue(null), isNull);
      expect(encodeValue('x'), 'x');
      expect(encodeValue(1), 1);
      expect(encodeValue(1.5), 1.5);
      expect(encodeValue(true), true);
    });

    test('writes enums by name', () {
      expect(encodeValue(Color.red), 'red');
    });

    test('calls toJson, also on what toJson leaves unencoded', () {
      final segment = Segment.fromJson({
        'from': {'x': 1, 'y': 2},
        'to': {'x': 3, 'y': 4},
      });
      expect(encodeValue(segment), {
        'from': {'x': 1, 'y': 2},
        'to': {'x': 3, 'y': 4},
      });
    });

    test('encodes lists and maps item by item', () {
      expect(
        encodeValue([
          Point(1, 2),
          {'c': Color.green},
        ]),
        [
          {'x': 1, 'y': 2},
          {'c': 'green'},
        ],
      );
    });

    test('rejects a value without toJson', () {
      expect(() => encodeValue(Opaque()), throwsArgumentError);
    });
  });
}
