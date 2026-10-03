import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

/// The graph file a graph screen shows, live (spec §9 «Открыть»): read when
/// started, and read again whenever it changes.
///
/// It is looked at on every file system event in its directory and every
/// [pollInterval] besides, since events come late and get merged. A file
/// that cannot be read is an [error], and the last [graph] read stays: the
/// developer is likely in the middle of an edit. So does a file that is
/// gone ([fileMissing]): an editor may save a file by deleting it first.
class GraphFileSource extends ChangeNotifier {
  GraphFileSource({
    required this.file,
    this.pollInterval = const Duration(milliseconds: 500),
  });

  /// The graph file: `nanoflow.graph.json`.
  final String file;

  /// How often the file is looked at when no file system event tells.
  final Duration pollInterval;

  GraphFile? _graph;
  String? _error;
  bool _fileMissing = false;

  /// The text last read from the file.
  String? _text;

  Timer? _poll;
  StreamSubscription<FileSystemEvent>? _events;
  bool _reading = false;
  bool _readAgain = false;
  bool _disposed = false;

  /// The last graph file read; `null` while none has been.
  GraphFile? get graph => _graph;

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
      _text = null;
      if (!_disposed) _update(missing: true, error: null);
      return;
    } on FileSystemException catch (e) {
      _text = null;
      if (!_disposed) _update(error: 'cannot be read: ${e.message}');
      return;
    }
    if (_disposed) return;
    if (text == _text) {
      _update(error: _error);
      return;
    }
    _text = text;
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      _update(error: _jsonError(e));
      return;
    }
    if (json is! Map<String, Object?>) {
      _update(error: 'the file is not a JSON object');
      return;
    }
    try {
      final graph = GraphFile.fromJson(json);
      _update(error: null, graph: graph == _graph ? _graph : graph);
    } on FormatException catch (e) {
      _update(error: e.message);
    }
  }

  /// Sets what is known of the file, and tells listeners when it changed.
  void _update({
    required String? error,
    GraphFile? graph,
    bool missing = false,
  }) {
    final next = graph ?? _graph;
    if ((next, error, missing) == (_graph, _error, _fileMissing)) return;
    _graph = next;
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
