/// Whether a graph file matches the code it was read from (spec §9
/// «Свежесть», «Сессия»; decision 8): the sources and binaries next to it,
/// and the code a session ran on.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import 'graph_file_source.dart';

/// How a graph file stands against the code next to it.
final class Freshness {
  const Freshness({required this.stale, required this.changed});

  /// Whether the graph may not match the code next to it.
  final bool stale;

  /// What next to the file differs from what the file says, by its path
  /// from the file's directory: its sources, edited or gone (`lib/review.dart`),
  /// then the binaries of its `builds` built again (`review`). May be empty
  /// when [stale]: the file's fingerprint is not that of its own sources.
  final List<String> changed;

  @override
  bool operator ==(Object other) =>
      other is Freshness &&
      other.stale == stale &&
      listEquals(other.changed, changed);

  @override
  int get hashCode => Object.hash(stale, Object.hashAll(changed));

  @override
  String toString() => 'Freshness(stale: $stale, changed: $changed)';
}

/// How [graph], the graph file in [dir], stands against the code next to it.
///
/// When any of its `sources` is in [dir], their fingerprint (spec §6.2) is
/// computed as they are now and compared with the file's; sources that are
/// not there are a built program's directory, and are not compared. Each
/// binary of its `builds` that is in [dir] has its bytes hashed and compared.
/// [hashes] keeps the hashes of files that have not changed since.
Future<Freshness> checkFreshness(
  GraphFile graph,
  String dir, {
  FileHashes? hashes,
}) async {
  final files = hashes ?? FileHashes();
  final changed = <String>[];
  var stale = false;

  final sources = <String, String>{};
  for (final path in graph.sources.keys) {
    final hash = await files.source(p.joinAll([dir, ...path.split('/')]));
    if (hash != null) sources[path] = hash;
  }
  if (sources.isNotEmpty) {
    stale = fingerprintOf(sources) != graph.fingerprint;
    changed.addAll(
      [
        for (final MapEntry(key: path, value: hash) in graph.sources.entries)
          if (sources[path] != hash) path,
      ]..sort(),
    );
  }

  for (final name in graph.builds.keys.toList()..sort()) {
    final hash = await files.binary(p.join(dir, name));
    if (hash != null && hash != graph.builds[name]) changed.add(name);
  }
  return Freshness(
    stale: stale || changed.isNotEmpty,
    changed: List.unmodifiable(changed),
  );
}

/// The hashes of files, kept while a file's time and size stay the same: a
/// graph file is checked again every second, and its sources and binaries
/// rarely change.
final class FileHashes {
  final Map<String, _Hashed> _sources = {};
  final Map<String, _Hashed> _binaries = {};

  /// The source hash (spec §6.2) of the file at [path]; `null` when it is
  /// not there.
  Future<String?> source(String path) => _hash(
    path,
    _sources,
    () async => sourceHash(await File(path).readAsBytes()),
  );

  /// The hash of the bytes of the file at [path]; `null` when it is not
  /// there. A program may be tens of megabytes: it is read and hashed in an
  /// isolate of its own, so that the screen does not stop meanwhile.
  Future<String?> binary(String path) => _hash(
    path,
    _binaries,
    () => Isolate.run(() => bytesHash(File(path).readAsBytesSync())),
  );

  Future<String?> _hash(
    String path,
    Map<String, _Hashed> known,
    Future<String> Function() hash,
  ) async {
    final stat = await FileStat.stat(path);
    if (stat.type != FileSystemEntityType.file) {
      known.remove(path);
      return null;
    }
    final kept = known[path];
    if (kept != null &&
        kept.modified == stat.modified &&
        kept.size == stat.size) {
      return kept.hash;
    }
    final String hashed;
    try {
      hashed = await hash();
    } on FileSystemException {
      known.remove(path);
      return null;
    }
    known[path] = (modified: stat.modified, size: stat.size, hash: hashed);
    return hashed;
  }
}

typedef _Hashed = ({DateTime modified, int size, String hash});

/// How the code a session ran on stands against the graph it is shown with.
enum CodeCheck {
  /// The code is the one the graph was read from, or a build of it.
  matches,

  /// The code is neither: the session ran on other code.
  otherCode,

  /// The session recorded no hash of its code.
  notChecked,
}

/// Whether [code], the hash of the code a session ran on, is that of
/// [graph]: its `fingerprint` or one of its `builds`.
CodeCheck checkCode(String? code, GraphFile graph) => code == null
    ? CodeCheck.notChecked
    : code == graph.fingerprint || graph.builds.containsValue(code)
    ? CodeCheck.matches
    : CodeCheck.otherCode;

/// The [Freshness] of the graph file of [source], kept up to date once
/// started: checked when the file has been read and every [interval], so
/// that an edit of the sources shows.
class FreshnessWatch extends ChangeNotifier {
  FreshnessWatch(this.source, {this.interval = const Duration(seconds: 1)});

  final GraphFileSource source;

  /// How often the code next to the file is looked at again.
  final Duration interval;

  final FileHashes _hashes = FileHashes();
  Freshness? _freshness;
  Timer? _timer;
  bool _started = false;
  bool _checking = false;
  bool _checkAgain = false;
  bool _disposed = false;

  /// How the graph file read last stands against the code next to it;
  /// `null` while no graph file has been read and checked.
  Freshness? get freshness => _freshness;

  /// Checks now, then whenever the graph file changes and every [interval].
  void start() {
    if (_started) return;
    _started = true;
    source.addListener(_sourceChanged);
    _timer = Timer.periodic(interval, (_) => unawaited(_check()));
    unawaited(_check());
  }

  void _sourceChanged() => unawaited(_check());

  /// Checks, and once more when asked to while it checks.
  Future<void> _check() async {
    if (_checking) {
      _checkAgain = true;
      return;
    }
    _checking = true;
    try {
      do {
        _checkAgain = false;
        final graph = source.graph;
        final freshness = graph == null
            ? null
            : await checkFreshness(
                graph,
                p.dirname(source.file),
                hashes: _hashes,
              );
        if (_disposed) return;
        if (freshness != _freshness) {
          _freshness = freshness;
          notifyListeners();
        }
      } while (_checkAgain);
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (_started) source.removeListener(_sourceChanged);
    super.dispose();
  }
}
