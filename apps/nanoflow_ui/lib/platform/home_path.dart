import 'dart:io';

/// [path] with the home directory written as `~`, the way the mockups show
/// paths: `~/Projects/review/review.yaml`. [home] defaults to `$HOME`.
String abbreviateHome(String path, {String? home}) {
  var dir = home ?? Platform.environment['HOME'] ?? '';
  while (dir.endsWith('/')) {
    dir = dir.substring(0, dir.length - 1);
  }
  if (dir.isEmpty) return path;
  if (path == dir) return '~';
  if (path.startsWith('$dir/')) return '~${path.substring(dir.length)}';
  return path;
}
