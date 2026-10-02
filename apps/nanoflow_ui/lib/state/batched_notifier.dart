import 'dart:async';

import 'package:flutter/foundation.dart';

/// A [ChangeNotifier] that tells its listeners of many changes at once: at
/// most once per [batch], so that a burst of changes rebuilds the screen
/// once.
mixin BatchedNotifier on ChangeNotifier {
  /// How long changes gather before listeners hear of them.
  Duration get batch;

  Timer? _announcing;
  bool _disposed = false;

  /// Tells listeners once [batch] has passed, with whatever else changed by
  /// then.
  void notifyLater() {
    if (!_disposed) _announcing ??= Timer(batch, notifyNow);
  }

  /// Tells listeners now, of this and of what [notifyLater] still holds.
  void notifyNow() {
    _announcing?.cancel();
    _announcing = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _announcing?.cancel();
    super.dispose();
  }
}
