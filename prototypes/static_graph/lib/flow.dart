/// The API a workflow function is written against: here only what the
/// extractor needs to recognise. A step runs its body; the real library
/// would journal it and return the saved result when the function is
/// replayed.
library;

import 'dart:async';

/// One run of a workflow function.
class Flow {
  /// Runs [body] as the step [name]: a string literal, unique in the
  /// function, so that a step of a run is matched to its node.
  Future<T> step<T>(String name, FutureOr<T> Function() body) async => body();
}
