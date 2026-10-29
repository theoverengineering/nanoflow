import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../state/store_place.dart';

/// A graph file opened earlier, with the store its sessions were read from:
/// `null` for `runs/` next to it.
typedef RecentGraph = ({String path, StorePlace? store, DateTime openedAt});

/// Whether [path] names the graph file of a graph, `<name>.graph.json`: not
/// that of a whole package, `nanoflow.graph.json`, which describe no longer
/// writes ([isPackageGraphFile]).
bool isGraphFile(String path) {
  final name = p.basename(path);
  return name.endsWith(graphFileSuffix) &&
      name.length > graphFileSuffix.length &&
      !isPackageGraphFile(path);
}

/// Whether [path] names the graph file of a whole package,
/// `nanoflow.graph.json`, which describe wrote before each graph had a file
/// of its own.
bool isPackageGraphFile(String path) => p.basename(path) == graphFileName;

/// The start screen's `Recently opened` list: newest first, each graph file
/// with each store once.
///
/// Kept in the app's preferences as a JSON list of `{path, store, openedAt}`,
/// the store as `fs:…` or `sqlite:…` and only for a graph opened with one,
/// the time in UTC ISO-8601. Only graph files are listed ([isGraphFile]):
/// what the app opened when graphs were YAML files, or when a package had
/// one graph file, cannot be opened now.
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

  /// Puts [path] with [store] on top, opened [at]; an earlier entry for them
  /// goes away.
  Future<void> opened(String path, DateTime at, {StorePlace? store}) =>
      _change([
        (path: path, store: store, openedAt: at),
        ..._graphs.where((g) => g.path != path || g.store != store),
      ]);

  Future<void> remove(String path, {StorePlace? store}) =>
      _change([..._graphs.where((g) => g.path != path || g.store != store)]);

  Future<void> _change(List<RecentGraph> graphs) async {
    _graphs = graphs;
    notifyListeners();
    try {
      await _prefs.setString(
        _key,
        json.encode([
          for (final g in graphs)
            {
              'path': g.path,
              if (g.store case final store?) 'store': '$store',
              'openedAt': g.openedAt.toUtc().toIso8601String(),
            },
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
              store: switch (entry['store']) {
                final String store => StorePlace.parse(store),
                _ => null,
              },
              openedAt: DateTime.parse(entry['openedAt']! as String),
            ),
      ];
    } on Object {
      return [];
    }
  }
}
