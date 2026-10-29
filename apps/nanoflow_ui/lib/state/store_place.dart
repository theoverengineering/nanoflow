import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_reader/nanoflow_reader.dart';
import 'package:nanoflow_sqlite/nanoflow_sqlite.dart';
import 'package:path/path.dart' as p;

import 'project_dir.dart';

/// Where the sessions of a graph are (storage design §6.8), named as on the
/// command line: `fs:<runs directory>` or `sqlite:<database file>`. The app
/// cannot be given the code of an adapter, only this.
final class StorePlace {
  const StorePlace._(this.scheme, this.path);

  /// The `runs` directory [path].
  const StorePlace.files(String path) : this._('fs', path);

  /// The SQLite database [path].
  const StorePlace.sqlite(String path) : this._('sqlite', path);

  /// The place [text] names: `fs:` or `sqlite:` and a path, where `~` at its
  /// start is [home], by default `$HOME`; a relative path is from the
  /// working directory.
  ///
  /// Throws a [FormatException] that names what is wrong: a scheme it does
  /// not know, or no path.
  factory StorePlace.parse(String text, {String? home}) {
    final colon = text.indexOf(':');
    if (colon < 0) {
      throw FormatException(
        'a store is fs:<runs directory> or sqlite:<database file>, not '
        '"$text"',
      );
    }
    final scheme = text.substring(0, colon);
    var path = text.substring(colon + 1);
    if (path.isEmpty) throw FormatException('the store "$text" has no path');
    if (path == '~' || path.startsWith('~/')) {
      path =
          '${home ?? Platform.environment['HOME'] ?? ''}${path.substring(1)}';
    }
    path = p.normalize(p.absolute(path));
    return switch (scheme) {
      'fs' => StorePlace.files(path),
      'sqlite' => StorePlace.sqlite(path),
      _ => throw FormatException(
        'unknown store "$scheme": a store is fs:<runs directory> or '
        'sqlite:<database file>',
      ),
    };
  }

  /// The place of the sessions of the graph file [file] when none is given:
  /// `runs/` in its project directory ([projectDirOf]).
  factory StorePlace.nextTo(String file) =>
      StorePlace.files(runsDirOf(projectDirOf(file)));

  /// `fs` or `sqlite`.
  final String scheme;

  /// The `runs` directory or the database file.
  final String path;

  /// What the place is called in the header: `runs/` — the directory's
  /// name —, or the database's file name.
  String get name =>
      scheme == 'sqlite' ? p.basename(path) : '${p.basename(path)}/';

  /// A reader of the sessions here.
  SessionReader reader() => switch (scheme) {
    'sqlite' => SqliteReader(path),
    _ => FsReader(runsDir: path),
  };

  @override
  bool operator ==(Object other) =>
      other is StorePlace && other.scheme == scheme && other.path == path;

  @override
  int get hashCode => Object.hash(scheme, path);

  @override
  String toString() => '$scheme:$path';
}
