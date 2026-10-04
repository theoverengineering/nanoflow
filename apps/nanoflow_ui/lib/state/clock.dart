import 'dart:async';

import 'package:flutter/foundation.dart';

/// The current time, and a tick every [interval] for what shows durations
/// that grow while something runs: `Running for 12m 26s`, a running effect's
/// `Took`.
///
/// It ticks only while someone listens.
class LiveClock extends ChangeNotifier {
  /// [now] defaults to the wall clock; tests pass a fixed one.
  LiveClock({
    DateTime Function()? now,
    this.interval = const Duration(seconds: 1),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Duration interval;
  Timer? _ticks;

  DateTime now() => _now();

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _ticks ??= Timer.periodic(interval, (_) => notifyListeners());
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _ticks?.cancel();
      _ticks = null;
    }
  }

  @override
  void dispose() {
    _ticks?.cancel();
    super.dispose();
  }
}
