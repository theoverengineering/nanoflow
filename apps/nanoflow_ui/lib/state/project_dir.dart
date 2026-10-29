import 'dart:io';

import 'package:path/path.dart' as p;

/// The project directory of the graph file [file] (file per graph design
/// §5): what `runs/` is next to, and what the places in its code and its
/// sources are from.
///
/// A graph's file is next to its Dart file under `lib/` or `bin/`: the
/// project directory is the one over the nearest `lib/` or `bin/` above the
/// file that has a `pubspec.yaml` — a source directory may be named `lib`
/// too —; without one, as next to a built program, over the nearest; with
/// neither above, the file's directory.
String projectDirOf(String file) {
  final dir = p.dirname(file);
  String? nearest;
  for (var at = dir; p.dirname(at) != at; at = p.dirname(at)) {
    if (p.basename(at) case 'lib' || 'bin') {
      final over = p.dirname(at);
      if (File(p.join(over, 'pubspec.yaml')).existsSync()) return over;
      nearest ??= over;
    }
  }
  return nearest ?? dir;
}
