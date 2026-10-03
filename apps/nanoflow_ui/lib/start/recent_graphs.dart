import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// A graph file opened earlier.
typedef RecentGraph = ({String path, DateTime openedAt});

/// Whether [path] names a graph file: `nanoflow.graph.json`, or another
/// `*.graph.json`.
bool isGraphFile(String path) {
  final name = p.basename(path);
  return name.endsWith('.graph.json') && name.length > '.graph.json'.length;
}

/// The start screen's `Recently opened` list: newest first, each path once.
///
/// Kept in the app's preferences as a JSON list of `{path, openedAt}`, the
/// time in UTC ISO-8601. Only graph files are listed ([isGraphFile]): what
/// the app opened when graphs were YAML files cannot be opened now.
///
/// Changes show at once; saving them finishes later, and a save that fails
/// is reported to [FlutterError.reportError] rather than to the caller: the
/// list on screen stays right either way.
class RecentGraphs extends ChangeNotifier {
  RecentGraphs(this._prefs) : _graphs = _read(_prefs.getString(_key));

  static const _key = 'recentGraphs';

  final SharedPreferences _prefs;
  List<RecentGraph> _graphs;

  List<RecentGraph> get graphs => List.unmodifiable(_graphs);

  /// Puts [path] on top, opened [at]; an earlier entry for it goes away.
  Future<void> opened(String path, DateTime at) => _change([
    (path: path, openedAt: at),
    ..._graphs.where((g) => g.path != path),
  ]);

  Future<void> remove(String path) =>
      _change([..._graphs.where((g) => g.path != path)]);

  Future<void> _change(List<RecentGraph> graphs) async {
    _graphs = graphs;
    notifyListeners();
    try {
      await _prefs.setString(
        _key,
        json.encode([
          for (final g in graphs)
            {'path': g.path, 'openedAt': g.openedAt.toUtc().toIso8601String()},
        ]),
      );
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'nanoflow',
          context: ErrorDescription('while saving the recently opened graphs'),
        ),
      );
    }
  }

  /// The stored list; one that cannot be read is dropped rather than keep
  /// the app from starting.
  static List<RecentGraph> _read(String? stored) {
    if (stored == null) return [];
    try {
      return [
        for (final entry in (json.decode(
          stored,
        ) as List<Object?>).cast<Map<String, Object?>>())
          if (entry['path']! as String case final path when isGraphFile(path))
            (
              path: path,
              openedAt: DateTime.parse(entry['openedAt']! as String),
            ),
      ];
    } on Object {
      return [];
    }
  }
}
