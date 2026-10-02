import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs before every test file under test/.
///
/// Loads the app's own fonts (Geist, Geist Mono — pubspec.yaml), so screens
/// and goldens show real text rather than the test font's boxes, and keeps
/// every golden in test/goldens/.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadAppFonts();
  // The comparator resolves golden names next to the file it is given.
  goldenFileComparator = LocalFileComparator(
    Uri.file('${Directory.current.path}/test/goldens/golden_test.dart'),
  );
  await testMain();
}

Future<void> _loadAppFonts() async {
  final manifest = json.decode(
    await rootBundle.loadString('FontManifest.json'),
  ) as List<Object?>;
  for (final family in manifest.cast<Map<String, Object?>>()) {
    final loader = FontLoader(family['family']! as String);
    for (final font
        in (family['fonts']! as List<Object?>).cast<Map<String, Object?>>()) {
      loader.addFont(rootBundle.load(font['asset']! as String));
    }
    await loader.load();
  }
}
