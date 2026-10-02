import 'package:flutter/foundation.dart';
import 'package:nanoflow_reader/nanoflow_reader.dart';

import 'batched_notifier.dart';

/// A fork's outcome, once read: any JSON value, `null` included.
typedef Outcome = ({Object? value});

/// The outcome in the document with the given id, or `null` while it is not
/// known.
typedef OutcomeOf = Outcome? Function(String documentId);

/// Reads the value of the document [documentId] of the session [sessionId].
typedef ReadDocument = Future<Object?> Function(
  String sessionId,
  String documentId,
);

/// The outcomes of fork steps: the values of their output documents, read
/// when first asked for and kept.
///
/// The feed tells only that a document is there; its value is read on
/// request. An outcome is unknown until it has been read.
class Outcomes extends ChangeNotifier with BatchedNotifier {
  Outcomes(this._read, {this.batch = const Duration(milliseconds: 50)});

  /// Outcomes read by [reader].
  Outcomes.read(
    FsReader reader, {
    Duration batch = const Duration(milliseconds: 50),
  }) : this(reader.documentValue, batch: batch);

  final ReadDocument _read;

  @override
  final Duration batch;

  final Map<String, Outcome> _values = {};
  final Set<String> _reading = {};
  final Map<String, String> _problems = {};

  /// The outcome in the document [documentId], or `null` while it is not
  /// known.
  Outcome? operator [](String documentId) => _values[documentId];

  /// Documents that could not be read, with why.
  Map<String, String> get problems => Map.unmodifiable(_problems);

  /// Starts reading those of [documentIds] of the session [sessionId] that
  /// have not been read or tried yet.
  void load(String sessionId, Iterable<String> documentIds) {
    for (final id in documentIds) {
      if (_values.containsKey(id) ||
          _problems.containsKey(id) ||
          !_reading.add(id)) {
        continue;
      }
      _read(sessionId, id).then(
        (value) {
          _reading.remove(id);
          _values[id] = (value: value);
          notifyLater();
        },
        onError: (Object error) {
          _reading.remove(id);
          _problems[id] = '$error';
          notifyLater();
        },
      );
    }
  }
}
