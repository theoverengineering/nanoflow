// The types codecs know beyond JSON and classes with a codec: enums
// registered with addEnum, and records of two positional fields.

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

/// A value with a toJson whose type has no codec.
final class Unregistered {
  Map<String, Object?> toJson() => {'n': 1};
}

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

    test('with a field that is JSON only through its toJson, declared as a '
        'type with no codec that reads it, is a CodecException', () {
      final codecs = Codecs()..addEnum(Verdict.values);
      expect(
        () => codecs.encode<(Verdict, Object)>((Verdict.pass, Unregistered())),
        throwsA(
          isA<CodecException>().having(
            (e) => e.reason,
            'reason',
            contains('a Unregistered is JSON only through its toJson'),
          ),
        ),
      );
    });
  });
}
