import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A graph file opened earlier.
typedef RecentGraph = ({String path, DateTime openedAt});

/// The start screen's `Recently opened` list: newest first, each path once.
///
/// Kept in the app's preferences as a JSON list of `{path, openedAt}`, the
/// time in UTC ISO-8601. Changes show at once; saving them finishes later.
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
    await _prefs.setString(
      _key,
      json.encode([
        for (final g in graphs)
          {'path': g.path, 'openedAt': g.openedAt.toUtc().toIso8601String()},
      ]),
    );
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
          (
            path: entry['path']! as String,
            openedAt: DateTime.parse(entry['openedAt']! as String),
          ),
      ];
    } on Object {
      return [];
    }
  }
}
