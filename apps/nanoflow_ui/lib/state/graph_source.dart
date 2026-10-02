import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
///
/// A `nanoflow-yaml` that exits is started again: after [restartDelay], twice
/// as long after each exit in a row, up to [maxRestartDelay]; while the graph
/// file is gone, once it is back. An exit counts as one in a row unless the
/// run stayed up at least [maxRestartDelay], so a program that describes the
/// graph and dies is not started every second. The [programProblem] stays
/// until it describes the graph again.
class GraphSource extends ChangeNotifier {
  GraphSource({
    required this.file,
    required this.shell,
    this.fileCheckInterval = const Duration(seconds: 1),
    this.restartDelay = const Duration(seconds: 1),
    this.maxRestartDelay = const Duration(seconds: 30),
  });

  /// The graph file.
  final String file;

  /// How often [fileMissing] is looked at again.
  final Duration fileCheckInterval;

  /// How long after it exits `nanoflow-yaml` is started again.
  final Duration restartDelay;

  /// The longest wait before `nanoflow-yaml` is started again.
  final Duration maxRestartDelay;

  /// How many of the last lines of stderr a program that exited shows.
  static const stderrLines = 20;

  /// How the programs are found and started.
  final Shell shell;

  Graph? _graph;
  List<String> _errors = const [];
  SourceProblem? _programProblem;
  String? _checkProblem;
  bool _fileMissing = false;

  String? _yaml;
  String? _nanoflow;
  Process? _watch;
  Process? _check;
  Timer? _fileTimer;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final List<String> _stderr = [];

  /// How many times in a row `nanoflow-yaml` has exited without describing
  /// the graph in between.
  int _exits = 0;

  /// Starts `nanoflow-yaml` again, while it waits to.
  Timer? _restart;

  /// How long the running `nanoflow-yaml` has been up.
  final Stopwatch _up = Stopwatch();

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
  /// exited and has not described the graph since.
  SourceProblem? get programProblem => _programProblem;

  /// Why descriptions go unchecked: `nanoflow` is not on the PATH.
  String? get checkProblem => _checkProblem;

  /// Whether the graph file is gone; the last [graph] stays.
  bool get fileMissing => _fileMissing;

  /// How long `nanoflow-yaml` waits to start again after it has exited
  /// [exits] times in a row.
  Duration restartDelayAfter(int exits) {
    final delay = restartDelay * math.pow(2, math.min(exits - 1, 30));
    return delay < maxRestartDelay ? delay : maxRestartDelay;
  }

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
    _yaml = yaml;
    await _run();
  }

  /// Starts `nanoflow-yaml` and follows what it prints until it exits.
  Future<void> _run() async {
    _stderr.clear();
    final Process watch;
    try {
      watch = await shell.start(_yaml!, [
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
      _startAgainLater();
      notifyListeners();
      return;
    }
    if (_disposed) {
      watch.kill();
      return;
    }
    _watch = watch;
    _up
      ..reset()
      ..start();
    final output = [
      _lines(watch.stdout).listen(_described),
      _lines(watch.stderr).listen(_keepStderr),
    ];
    _subscriptions.addAll(output);
    final printed = Future.wait([
      for (final subscription in output) subscription.asFuture<void>(),
    ]).then<void>((_) {}, onError: (Object _) {});
    unawaited(
      watch.exitCode.then((code) async {
        // Its last description and its last words count: they are read
        // before the exit is told, unless something it started holds them.
        // What that prints later is not this graph's any more.
        await printed.timeout(const Duration(seconds: 1), onTimeout: () {});
        for (final subscription in output) {
          _subscriptions.remove(subscription);
          unawaited(subscription.cancel());
        }
        _exited(code);
      }),
    );
    notifyListeners();
  }

  void _described(String line) {
    if (_disposed) return;
    final Object? json;
    try {
      json = jsonDecode(line);
    } on FormatException {
      return;
    }
    // A line that is not a description is something else the program printed.
    if (json is! Map<String, Object?>) return;
    // It works again; whether for good, its exit, if any, will tell.
    if (_programProblem != null) {
      _programProblem = null;
      notifyListeners();
    }
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
      _errors = List.unmodifiable(errors);
      return;
    }
    try {
      _graph = GraphDescription.fromJson(jsonDecode(line)).graph;
      _errors = const [];
    } on FormatException catch (e) {
      // Checked or not, a graph the app cannot read is not shown.
      if (errors != null) _errors = List.unmodifiable([e.message]);
    }
  }

  void _keepStderr(String line) {
    _stderr.add(line);
    if (_stderr.length > stderrLines) _stderr.removeAt(0);
  }

  void _exited(int code) {
    if (_disposed) return;
    _watch = null;
    _up.stop();
    // Up long enough, it exited for a reason of its own: waiting starts over.
    if (_up.elapsed >= maxRestartDelay) _exits = 0;
    _programProblem = SourceProblem(
      'nanoflow-yaml exited with code $code',
      _stderr.join('\n'),
    );
    _startAgainLater();
    notifyListeners();
  }

  /// Starts `nanoflow-yaml` again after a while, longer after each exit in a
  /// row.
  void _startAgainLater() {
    _exits++;
    _startWhenFileIsThere(restartDelayAfter(_exits));
  }

  /// Starts `nanoflow-yaml` after [delay] if the graph file is there; else
  /// looks for the file every [restartDelay] and starts it once the file is
  /// back. What it sees of the file goes to [fileMissing] too: the
  /// file may be gone only between two of [_lookAtFile]'s looks.
  void _startWhenFileIsThere(Duration delay) {
    _restart = Timer(delay, () async {
      _restart = null;
      final missing = !await File(file).exists();
      if (_disposed) return;
      _fileIs(missing: missing);
      if (missing) {
        _startWhenFileIsThere(restartDelay);
      } else {
        unawaited(_run());
      }
    });
  }

  Future<void> _lookAtFile() async {
    final missing = !await File(file).exists();
    if (!_disposed) _fileIs(missing: missing);
  }

  /// Tells listeners when the graph file has gone or come back.
  void _fileIs({required bool missing}) {
    if (missing == _fileMissing) return;
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
    _restart?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _watch?.kill();
    _check?.kill();
    super.dispose();
  }
}
