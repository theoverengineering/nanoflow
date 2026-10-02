import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/state/schema_labels.dart';

import 'support.dart';

void main() {
  final types = reviewGraph['types']! as Map<String, Object?>;

  group('the label of a type', () {
    test('is the reference, for a type from types', () {
      expect(typeLabel({r'$ref': '#/Change'}), '#/Change');
    });

    test('is a short description of any other schema', () {
      expect(typeLabel({'type': 'string'}), 'string');
      expect(typeLabel({'type': 'object'}), 'object');
      expect(
        typeLabel({
          'type': 'array',
          'items': {'type': 'string'},
        }),
        'string[]',
      );
      expect(
        typeLabel({
          'type': 'array',
          'items': {r'$ref': '#/Change'},
        }),
        '#/Change[]',
      );
      expect(typeLabel({'type': 'array'}), 'array');
      expect(
        typeLabel({
          'type': ['string', 'null'],
        }),
        'string | null',
      );
      expect(
        typeLabel({
          'enum': ['a', 'b'],
        }),
        'enum',
      );
      expect(typeLabel({'const': 'go'}), '"go"');
      expect(
        typeLabel({
          'anyOf': [
            {'type': 'integer'},
            {r'$ref': '#/Change'},
          ],
        }),
        'integer | #/Change',
      );
      expect(typeLabel(<String, Object?>{}), 'any');
      expect(typeLabel(true), 'any');
      expect(typeLabel({'title': 'Change'}), 'Change');
      expect(typeLabel({'minimum': 1}), 'schema');
    });
  });

  group('the fields of a type', () {
    test('are the properties of the type it refers to', () {
      expect(fieldSummary({r'$ref': '#/Change'}, types), '{ id, path }');
    });

    test('mark arrays', () {
      expect(
        fieldSummary({r'$ref': '#/Report'}, types),
        '{ change, findings[] }',
      );
      expect(
        fieldSummary(
          {
            'type': 'object',
            'properties': {
              'tags': {r'$ref': '#/Tags'},
              'size': {'type': 'integer'},
            },
          },
          const {
            'Tags': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
        ),
        '{ tags[], size }',
      );
    });

    test('of an array are those of its items', () {
      expect(
        fieldSummary({
          'type': 'array',
          'items': {r'$ref': '#/Change'},
        }, types),
        '{ id, path }[]',
      );
    });

    test('are none for a type without properties', () {
      expect(fieldSummary({'type': 'string'}, types), isNull);
      expect(fieldSummary({r'$ref': '#/Missing'}, types), isNull);
      expect(
        fieldSummary({
          'type': 'object',
          'properties': <String, Object?>{},
        }, types),
        '{ }',
      );
    });

    test('of a type that refers to itself are read once', () {
      expect(
        fieldSummary(
          {r'$ref': '#/Loop'},
          const {
            'Loop': {r'$ref': '#/Loop'},
          },
        ),
        isNull,
      );
    });
  });
}
