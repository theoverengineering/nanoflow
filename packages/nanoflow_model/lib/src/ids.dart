import 'dart:math';

final Random _random = Random.secure();

final RegExp _idPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Returns a new random UUID v4 in lowercase: 36 characters, `8-4-4-4-12`.
String newId() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx: 8, 9, a or b
  final hex = [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')]
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Whether [s] is a lowercase hex UUID in the `8-4-4-4-12` form.
///
/// Checks the form only, not the UUID version.
bool isId(String s) => _idPattern.hasMatch(s);
