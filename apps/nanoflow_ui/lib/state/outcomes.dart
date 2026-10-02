import 'package:flutter/foundation.dart';
import 'package:nanoflow_reader/nanoflow_reader.dart';

import 'batched_notifier.dart';

/// A fork's outcome, once read: any JSON value, `null` included.
typedef Outcome = ({Object? value});

/// What is known of the outcomes of forks: read, failed to read, or not yet.
abstract interface class KnownOutcomes {
  /// The outcome in the document [documentId], or `null` while it is not
  /// known.
  Outcome? operator [](String documentId);

  /// Why the document [documentId] could not be read; `null` when it was, or
  /// has not been tried.
  String? problemOf(String documentId);
}

/// Reads the value of the document [documentId] of the session [sessionId].
typedef ReadDocument = Future<Object?> Function(
  String sessionId,
  String documentId,
);

/// The outcomes of fork steps: the values of their output documents, read
/// when first asked for and kept.
///
/// The feed tells only that a document is there; its value is read on
/// request. An outcome is unknown until it has been read. A document that
/// could not be read is read again once the feed gives it again.
class Outcomes extends ChangeNotifier
    with BatchedNotifier
    implements KnownOutcomes {
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

  @override
  Outcome? operator [](String documentId) => _values[documentId];

  @override
  String? problemOf(String documentId) => _problems[documentId];

  /// The document [documentId] has been written: if it could not be read,
  /// the next [load] reads it again.
  void documentWritten(String documentId) {
    if (_problems.remove(documentId) != null) notifyLater();
  }

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
