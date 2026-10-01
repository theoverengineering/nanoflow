import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:test/test.dart';

void main() {
  group('newId', () {
    test('is a lowercase 8-4-4-4-12 hex UUID', () {
      expect(
        newId(),
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('is 36 characters long', () {
      expect(newId(), hasLength(36));
    });

    test('is unique across 1000 ids', () {
      final ids = {for (var i = 0; i < 1000; i++) newId()};

      expect(ids, hasLength(1000));
    });

    test('has the version nibble 4', () {
      for (var i = 0; i < 1000; i++) {
        expect(newId()[14], '4');
      }
    });

    test('has the variant nibble 8, 9, a or b, and uses all four', () {
      final variants = {for (var i = 0; i < 1000; i++) newId()[19]};

      expect(variants, {'8', '9', 'a', 'b'});
    });

    test('is accepted by isId', () {
      expect(isId(newId()), isTrue);
    });
  });

  group('isId', () {
    test('accepts lowercase 8-4-4-4-12 hex UUIDs', () {
      expect(isId('3f9c2a7e-5b1d-4c8e-9a6f-0d2e4b7c1a35'), isTrue);
      expect(isId('8e1f4b2a-6c3d-4f7e-b5a9-2d0c7e6f1b48'), isTrue);
      expect(isId('00000000-0000-4000-8000-000000000000'), isTrue);
    });

    test('rejects uppercase hex', () {
      expect(isId('3F9C2A7E-5B1D-4C8E-9A6F-0D2E4B7C1A35'), isFalse);
      expect(isId('3f9c2a7e-5b1d-4c8e-9a6f-0d2e4b7c1A35'), isFalse);
    });

    test('rejects non-hex characters', () {
      expect(isId('3f9c2a7g-5b1d-4c8e-9a6f-0d2e4b7c1a35'), isFalse);
    });

    test('rejects wrong lengths and dash positions', () {
      expect(isId(''), isFalse);
      expect(isId('3f9c2a7e-5b1d-4c8e-9a6f-0d2e4b7c1a3'), isFalse);
      expect(isId('3f9c2a7e-5b1d-4c8e-9a6f-0d2e4b7c1a355'), isFalse);
      expect(isId('3f9c2a7e5b1d4c8e9a6f0d2e4b7c1a35'), isFalse);
      expect(isId('3f9c2a7-e5b1d-4c8e-9a6f-0d2e4b7c1a35'), isFalse);
    });

    test('rejects braces, whitespace and a trailing newline', () {
      expect(isId('{3f9c2a7e-5b1d-4c8e-9a6f-0d2e4b7c1a35}'), isFalse);
      expect(isId(' 3f9c2a7e-5b1d-4c8e-9a6f-0d2e4b7c1a35'), isFalse);
      expect(isId('3f9c2a7e-5b1d-4c8e-9a6f-0d2e4b7c1a35\n'), isFalse);
    });
  });
}
