import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import 'project_dir.dart';

/// The graph file a graph screen shows, live (spec §9 «Открыть»): read when
/// started, and read again whenever it changes.
///
/// A graph's own file (file per graph design §5) is read with the files of
/// its subgraphs, by chain, from its project directory, and put together as
/// one graph file, as a session's snapshot is (`assembleGraphFile`); a
/// subgraph whose file cannot be read is left out. A graph file of a whole
/// package is read as it is.
///
/// It is looked at on every file system event in its directory and every
/// [pollInterval] besides, since events come late and get merged; the files
/// of its subgraphs only so. A file that cannot be read is an [error], and
/// the last [graph] read stays: the developer is likely in the middle of an
/// edit. So does a file that is gone ([fileMissing]): an editor may save a
/// file by deleting it first.
class GraphFileSource extends ChangeNotifier {
  GraphFileSource({
    required this.file,
    this.pollInterval = const Duration(milliseconds: 500),
  });

  /// The graph file: a graph's own `<name>.graph.json`, or a whole
  /// package's `nanoflow.graph.json`.
  final String file;

  /// How often the file is looked at when no file system event tells.
  final Duration pollInterval;

  GraphFile? _graph;
  bool _oneGraph = false;
  String? _error;
  bool _fileMissing = false;

  /// The texts last read: the file's, and those of its subgraphs' files, by
  /// their paths.
  Map<String, String>? _texts;

  Timer? _poll;
  StreamSubscription<FileSystemEvent>? _events;
  bool _reading = false;
  bool _readAgain = false;
  bool _disposed = false;

  /// The last graph file read; `null` while none has been.
  GraphFile? get graph => _graph;

  /// Whether [graph] was read from a graph's own file: it has that graph
  /// only, with its subgraphs, and the sessions of other graphs are not of a
  /// workflow it lacks.
  bool get oneGraph => _oneGraph;

  /// Why the file as it is now cannot be read: it is not JSON, or not a
  /// graph file (the message starts with the path of the field that is
  /// wrong). `null` when it is read, and while it is missing.
  String? get error => _error;

  /// Whether the file is gone; the last [graph] stays.
  bool get fileMissing => _fileMissing;

  /// Reads the file, then follows it.
  Future<void> start() async {
    await _read();
    if (_disposed) return;
    _poll = Timer.periodic(pollInterval, (_) => unawaited(_read()));
    try {
      _events = Directory(p.dirname(file))
          .watch()
          .where(_isAboutFile)
          .listen((_) => unawaited(_read()), onError: (Object _) {});
    } on FileSystemException {
      // Without events, the polls still find every change.
    }
  }

  /// Whether [event] may have changed the file: the rest of the directory,
  /// such as the sessions being written to `runs/`, does not count.
  bool _isAboutFile(FileSystemEvent event) =>
      p.equals(event.path, file) ||
      (event is FileSystemMoveEvent &&
          event.destination != null &&
          p.equals(event.destination!, file));

  /// Reads the file, and once more when asked to while it reads.
  Future<void> _read() async {
    if (_reading) {
      _readAgain = true;
      return;
    }
    _reading = true;
    try {
      do {
        _readAgain = false;
        await _readOnce();
      } while (_readAgain && !_disposed);
    } finally {
      _reading = false;
    }
  }

  Future<void> _readOnce() async {
    final String text;
    try {
      text = await File(file).readAsString();
    } on PathNotFoundException {
      // What comes back is read anew, even if it is what was there.
      _texts = null;
      if (!_disposed) _update(missing: true, error: null);
      return;
    } on FileSystemException catch (e) {
      _texts = null;
      if (!_disposed) _update(error: 'cannot be read: ${e.message}');
      return;
    }
    if (_disposed) return;
    final read = await _readGraph(text);
    if (_disposed) return;
    if (mapEquals(read.texts, _texts)) {
      _update(error: _error);
      return;
    }
    _texts = read.texts;
    if (read.error case final error?) {
      _update(error: error);
      return;
    }
    final graph = read.graph!;
    _update(
      error: null,
      graph: graph == _graph ? _graph : graph,
      oneGraph: read.oneGraph,
    );
  }

  /// Reads [text], the file's: a graph file of format 3 as it is; a graph's
  /// own file with those of its subgraphs, by chain. Gives the texts read by
  /// path, and the graph file or why there is none.
  Future<
    ({
      Map<String, String> texts,
      GraphFile? graph,
      bool oneGraph,
      String? error,
    })
  >
  _readGraph(String text) async {
    final texts = {file: text};
    Object? json;
    String? error;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      error = _jsonError(e);
    }
    if (error == null && json is! Map<String, Object?>) {
      error = 'the file is not a JSON object';
    }
    if (error != null || json is! Map<String, Object?>) {
      return (texts: texts, graph: null, oneGraph: false, error: error);
    }
    try {
      if (json['format'] != oneGraphFileFormat) {
        final graph = GraphFile.fromJson(json);
        return (texts: texts, graph: graph, oneGraph: false, error: null);
      }
      final root = projectDirOf(file);
      String pathOf(String file) =>
          p.split(p.relative(file, from: root)).join('/');
      final own = pathOf(file);
      final files = {own: OneGraphFile.fromJson(json)};
      final pending = [...files[own]!.subgraphs];
      while (pending.isNotEmpty) {
        final path = pending.removeLast();
        if (files.containsKey(path)) continue;
        final subgraph = p.joinAll([root, ...path.split('/')]);
        try {
          final text = await File(subgraph).readAsString();
          texts[subgraph] = text;
          if (jsonDecode(text) case final Map<String, Object?> json) {
            files[path] = OneGraphFile.fromJson(json);
            pending.addAll(files[path]!.subgraphs);
          }
        } on FileSystemException {
          continue;
        } on FormatException {
          continue;
        }
      }
      return (
        texts: texts,
        graph: assembleGraphFile(own, files),
        oneGraph: true,
        error: null,
      );
    } on FormatException catch (e) {
      return (texts: texts, graph: null, oneGraph: false, error: e.message);
    }
  }

  /// Sets what is known of the file, and tells listeners when it changed.
  void _update({
    required String? error,
    GraphFile? graph,
    bool? oneGraph,
    bool missing = false,
  }) {
    final next = graph ?? _graph;
    final nextOneGraph = oneGraph ?? _oneGraph;
    if ((next, nextOneGraph, error, missing) ==
        (_graph, _oneGraph, _error, _fileMissing)) {
      return;
    }
    _graph = next;
    _oneGraph = nextOneGraph;
    _error = error;
    _fileMissing = missing;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    unawaited(_events?.cancel());
    super.dispose();
  }
}

/// What is wrong with JSON [e] was thrown for, and where: `Unexpected end of
/// input at line 3, column 1`.
String _jsonError(FormatException e) {
  final offset = e.offset;
  final source = e.source;
  if (offset == null || source is! String) return e.message;
  final before = source.substring(0, math.min(offset, source.length));
  final line = '\n'.allMatches(before).length + 1;
  final column = before.length - before.lastIndexOf('\n');
  return '${e.message} at line $line, column $column';
}

/// The graph file in [json], a snapshot a session holds; `null` when it is
/// not one.
///
/// A snapshot is read once: the same [json] gives the same graph file.
GraphFile? readGraphFile(Object? json) {
  if (json is! Map<String, Object?>) return null;
  return (_snapshots[json] ??= (graph: _readSnapshot(json))).graph;
}

final Expando<({GraphFile? graph})> _snapshots = Expando('graph snapshots');

GraphFile? _readSnapshot(Map<String, Object?> json) {
  try {
    return GraphFile.fromJson(json);
  } on FormatException {
    return null;
  }
}
