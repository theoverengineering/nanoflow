import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;

import '../platform/shell.dart';

/// What the canvas says for `Current graph` while no description has passed
/// `nanoflow check`.
const noValidGraphYet = 'No valid graph yet';

/// The banner while the graph file is gone; the last graph read stays.
const fileUnavailable = 'File unavailable';

/// What is wrong with the program that gives the current graph.
final class SourceProblem {
  const SourceProblem(this.message, [this.details = '']);

  /// One line: `nanoflow-yaml exited with code 1`.
  final String message;

  /// More of it, such as the end of the program's stderr; may be empty.
  final String details;

  @override
  String toString() => details.isEmpty ? message : '$message\n$details';
}

/// The current graph of a graph file, live (docs/ui-spec.md «Что это», «Когда
/// что-то не так»).
///
/// Runs `nanoflow-yaml <file> --graph --watch` and hands each description it
/// prints to `nanoflow check` on stdin. The last description check passed is
/// the [graph]; the errors of the latest one are [errors]. Both programs are
/// found on the user's PATH.
class GraphSource extends ChangeNotifier {
  GraphSource({
    required this.file,
    required this.shell,
    this.fileCheckInterval = const Duration(seconds: 1),
  });

  /// The graph file.
  final String file;

  /// How often [fileMissing] is looked at again.
  final Duration fileCheckInterval;

  /// How many of the last lines of stderr a program that exited shows.
  static const stderrLines = 20;

  /// How the programs are found and started.
  final Shell shell;

  Graph? _graph;
  List<String> _errors = const [];
  SourceProblem? _programProblem;
  String? _checkProblem;
  bool _fileMissing = false;

  String? _nanoflow;
  Process? _watch;
  Process? _check;
  Timer? _fileTimer;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final List<String> _stderr = [];

  /// The latest description not yet checked, and whether one is being
  /// checked.
  String? _pending;
  bool _checking = false;
  bool _disposed = false;

  /// The last graph that passed `nanoflow check`; `null` while none has.
  /// Without `nanoflow` on the PATH, the last graph described.
  Graph? get graph => _graph;

  /// What `nanoflow check` found wrong with the latest description, one error
  /// per line; empty when it passed.
  List<String> get errors => _errors;

  /// Why there is no live graph: `nanoflow-yaml` is not on the PATH, or it
  /// exited.
  SourceProblem? get programProblem => _programProblem;

  /// Why descriptions go unchecked: `nanoflow` is not on the PATH.
  String? get checkProblem => _checkProblem;

  /// Whether the graph file is gone; the last [graph] stays.
  bool get fileMissing => _fileMissing;

  /// Finds the programs and starts `nanoflow-yaml`.
  Future<void> start() async {
    unawaited(_lookAtFile());
    _fileTimer = Timer.periodic(fileCheckInterval, (_) => _lookAtFile());
    final yaml = await shell.findExecutable('nanoflow-yaml');
    _nanoflow = await shell.findExecutable('nanoflow');
    if (_disposed) return;
    if (_nanoflow == null) {
      _checkProblem = 'nanoflow not found on PATH — graph not checked';
    }
    if (yaml == null) {
      _programProblem = const SourceProblem('nanoflow-yaml not found on PATH');
      notifyListeners();
      return;
    }
    final Process watch;
    try {
      watch = await shell.start(yaml, [
        file,
        '--graph',
        '--watch',
      ], workingDirectory: p.dirname(file));
    } on ProcessException catch (e) {
      if (_disposed) return;
      _programProblem = SourceProblem(
        'nanoflow-yaml could not start',
        e.message,
      );
      notifyListeners();
      return;
    }
    if (_disposed) {
      watch.kill();
      return;
    }
    _watch = watch;
    _subscriptions
      ..add(_lines(watch.stdout).listen(_described))
      ..add(_lines(watch.stderr).listen(_keepStderr));
    final printed = Future.wait([
      for (final subscription in _subscriptions) subscription.asFuture<void>(),
    ]).then<void>((_) {}, onError: (Object _) {});
    unawaited(
      watch.exitCode.then((code) async {
        // Its last description and its last words count: they are read
        // before the exit is told, unless something it started holds them.
        await printed.timeout(const Duration(seconds: 1), onTimeout: () {});
        _exited(code);
      }),
    );
    notifyListeners();
  }

  void _described(String line) {
    final Object? json;
    try {
      json = jsonDecode(line);
    } on FormatException {
      return;
    }
    // A line that is not a description is something else the program printed.
    if (json is! Map<String, Object?>) return;
    _pending = line;
    if (!_checking) unawaited(_checkPending());
  }

  /// Checks the latest description until none is left; one that a newer one
  /// has replaced while it was checked counts no more. A check that fails in
  /// an unexpected way is that description's error, and later ones are still
  /// checked.
  Future<void> _checkPending() async {
    _checking = true;
    try {
      while (_pending != null && !_disposed) {
        final line = _pending!;
        _pending = null;
        List<String>? errors;
        try {
          errors = await _checkLine(line);
        } on Object catch (error) {
          errors = ['nanoflow check could not run: $error'];
        }
        if (_disposed || _pending != null) continue;
        _apply(line, errors);
        notifyListeners();
      }
    } finally {
      _checking = false;
    }
  }

  /// The errors `nanoflow check` finds in [line]: empty when it passes,
  /// `null` when there is no `nanoflow` to ask.
  Future<List<String>?> _checkLine(String line) async {
    final nanoflow = _nanoflow;
    if (nanoflow == null) return null;
    final Process check;
    try {
      check = _check = await shell.start(nanoflow, ['check']);
    } on ProcessException catch (e) {
      _checkProblem = 'nanoflow check could not start: ${e.message}';
      return null;
    }
    // What it printed so far is enough if its output breaks off.
    final out = _lines(check.stdout).handleError((Object _) {}).toList();
    final err = _lines(check.stderr).handleError((Object _) {}).toList();
    try {
      check.stdin.writeln(line);
      await check.stdin.close();
    } on IOException {
      // It exited without reading; its exit code says why.
    }
    final code = await check.exitCode;
    _check = null;
    if (code == 0) return const [];
    final errors = [
      for (final error in await out)
        if (error.trim().isNotEmpty) error,
    ];
    if (errors.isNotEmpty) return errors;
    final why = (await err).where((l) => l.trim().isNotEmpty).lastOrNull;
    return [
      'nanoflow check exited with code $code${why == null ? '' : ': $why'}',
    ];
  }

  void _apply(String line, List<String>? errors) {
    if (errors != null && errors.isNotEmpty) {
      _errors = errors;
      return;
    }
    try {
      _graph = GraphDescription.fromJson(jsonDecode(line)).graph;
      _errors = const [];
    } on FormatException catch (e) {
      // Checked or not, a graph the app cannot read is not shown.
      if (errors != null) _errors = [e.message];
    }
  }

  void _keepStderr(String line) {
    _stderr.add(line);
    if (_stderr.length > stderrLines) _stderr.removeAt(0);
  }

  void _exited(int code) {
    if (_disposed) return;
    _watch = null;
    _programProblem = SourceProblem(
      'nanoflow-yaml exited with code $code',
      _stderr.join('\n'),
    );
    notifyListeners();
  }

  Future<void> _lookAtFile() async {
    final missing = !await File(file).exists();
    if (_disposed || missing == _fileMissing) return;
    _fileMissing = missing;
    notifyListeners();
  }

  static Stream<String> _lines(Stream<List<int>> bytes) => bytes
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter());

  @override
  void dispose() {
    _disposed = true;
    _fileTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _watch?.kill();
    _check?.kill();
    super.dispose();
  }
}
