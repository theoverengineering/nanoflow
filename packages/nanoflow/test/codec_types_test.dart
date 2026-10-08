// The types codecs know beyond JSON and classes with a codec: enums
// registered with addEnum, records of two positional fields, and the type a
// function of one parameter returns, which a graph's node gives.

import 'dart:async';

import 'package:nanoflow/nanoflow.dart';
import 'package:nanoflow/src/codecs.dart';
import 'package:test/test.dart';

enum Verdict { pass, fail }

sealed class Shape {
  static Shape fromJson(Map<String, Object?> json) =>
      json['r'] == null ? Square(json['a']! as int) : Circle(json['r']! as int);

  Map<String, Object?> toJson();
}

final class Square extends Shape {
  Square(this.a);

  final int a;

  @override
  Map<String, Object?> toJson() => {'a': a};
}

final class Circle extends Shape {
  Circle(this.r);

  final int r;

  @override
  Map<String, Object?> toJson() => {'r': r};
}

Future<Shape> makeShape(int n) async => Square(n);

Future<Circle> makeCircle(int n) async => Circle(n);

Future<Verdict> judge(String s) async => Verdict.pass;

Future<(Verdict, List<String>)> judgeWith(String s) async =>
    (Verdict.pass, [s]);

Future<List<Shape>> shapes(int n) async => [Square(n)];

Future<Map<String, int>> counts(int n) async => {'n': n};

Future<Shape?> maybeShape(int n) async => null;

Future<void> nothing(int n) async {}

Shape now(int n) => Square(n);

Future<Object> anything(int n) async => 1;

String name(int n) => '$n';

/// A value with a toJson whose type has no codec.
final class Unregistered {
  Map<String, Object?> toJson() => {'n': 1};
}

Future<(Verdict, Unregistered)> judgeUnregistered(String s) async =>
    (Verdict.pass, Unregistered());

Future<List<(int, Unregistered)>> listUnregistered(int n) async => [
  (n, Unregistered()),
];

FutureOr<int> twice(int n) => n * 2;

void main() {
  group('enums', () {
    test('an enum with addEnum is written by name and read back', () {
      final codecs = Codecs()..addEnum(Verdict.values);
      expect(codecs.encode<Verdict>(Verdict.fail), 'fail');
      expect(codecs.decode<Verdict>('fail'), Verdict.fail);
      expect(codecs.decode<List<Verdict?>>(['pass', null]), [
        Verdict.pass,
        null,
      ]);
    });

    test('an enum without addEnum is a CodecException', () {
      expect(
        () => Codecs().encode<Verdict>(Verdict.fail),
        throwsA(isA<CodecException>()),
      );
    });

    test('a name the enum has no value of does not decode', () {
      final codecs = Codecs()..addEnum(Verdict.values);
      expect(
        () => codecs.decode<Verdict>('maybe'),
        throwsA(isA<CodecException>()),
      );
    });
  });

  group('records of two positional fields', () {
    test('are written as a list and read back with their field types', () {
      final codecs = Codecs()..addEnum(Verdict.values);
      final json = codecs.encode<(Verdict, List<String>)>((
        Verdict.pass,
        ['a'],
      ));
      expect(json, [
        'pass',
        ['a'],
      ]);
      final back = codecs.decode<(Verdict, List<String>)>(json);
      expect(back.$1, Verdict.pass);
      expect(back.$2, isA<List<String>>().having((l) => l, 'items', ['a']));
    });

    test('of a class with a codec come back as that class', () {
      final codecs = Codecs()..add(Shape.fromJson);
      final json = codecs.encode<(int, Shape)>((1, Square(2)));
      expect(codecs.decode<(int, Shape)>(json).$2, isA<Square>());
    });
  });

  group('resultOf', () {
    late Codecs codecs;

    setUp(
      () => codecs = Codecs()
        ..add(Shape.fromJson)
        ..addEnum(Verdict.values),
    );

    test('decodes by the type the function returns', () {
      expect(codecs.resultOf(makeShape).decode({'r': 2}), isA<Circle>());
      expect(codecs.resultOf(judge).decode('fail'), Verdict.fail);
      expect(
        codecs.resultOf(judgeWith).decode([
          'pass',
          ['x'],
        ]),
        isA<(Verdict, List<String>)>()
            .having((r) => r.$1, 'verdict', Verdict.pass)
            .having((r) => r.$2, 'list', ['x']),
      );
      expect(
        codecs.resultOf(shapes).decode([
          {'a': 1},
        ]),
        isA<List<Shape>>(),
      );
      expect(codecs.resultOf(counts).decode({'n': 1}), isA<Map<String, int>>());
      expect(codecs.resultOf(maybeShape).decode(null), isNull);
      expect(codecs.resultOf(maybeShape).decode({'a': 1}), isA<Square>());
      expect(codecs.resultOf(name).decode('7'), '7');
      expect(codecs.resultOf(now).decode({'a': 1}), isA<Square>());
      expect(codecs.resultOf(twice).decode(4), 4);
      expect(codecs.resultOf(nothing).decode(null), isNull);
    });

    test('takes the codec of a supertype for a subtype without one', () {
      expect(codecs.resultOf(makeCircle).decode({'r': 3}), isA<Circle>());
    });

    test('encodes what comes back', () {
      expect(codecs.resultOf(makeShape).encode(Square(3)), {'a': 3});
      expect(codecs.resultOf(judgeWith).encode((Verdict.fail, ['y'])), [
        'fail',
        ['y'],
      ]);
      expect(codecs.resultOf(nothing).encode(null), isNull);
    });

    test('a field of a record that is JSON only through its toJson, with no '
        'codec of its type, is a CodecException, as a value of its own is', () {
      expect(
        () => codecs.resultOf(judgeUnregistered).encode((
          Verdict.pass,
          Unregistered(),
        )),
        throwsA(
          isA<CodecException>().having(
            (e) => e.reason,
            'reason',
            contains('a Unregistered is JSON only through its toJson'),
          ),
        ),
      );
      expect(
        () => codecs.resultOf(listUnregistered).encode([(1, Unregistered())]),
        throwsA(isA<CodecException>()),
      );
      expect(
        () => codecs.encode<(Verdict, Object)>((Verdict.pass, Unregistered())),
        throwsA(isA<CodecException>()),
      );
    });

    test('a value JSON only through toJson, returned as Object, is a '
        'CodecException', () {
      expect(
        () => codecs.resultOf(anything).encode(Square(1)),
        throwsA(isA<CodecException>()),
      );
    });
  });
}
