import 'package:nanoflow_reader/nanoflow_reader.dart';

/// What the details of a step read from the storage, on request: the step's
/// log as it grows, the values of its documents, and the files they are in
/// (docs/ui-spec.md «Logs», «Окно деталей шага»).
abstract interface class StepFiles {
  /// The log of the step [stepId] of the session [sessionId]: the text
  /// written so far, then what is appended, until cancelled.
  Stream<String> stepLog(String sessionId, String stepId);

  /// The value of the document [documentId].
  Future<Object?> documentValue(String sessionId, String documentId);

  /// The directory of the step [stepId]; `null` while it is not known, and
  /// for a storage without files.
  String? stepPath(String stepId);

  /// The file of the step [stepId]'s log; `null` while it is not known, and
  /// for a storage without files.
  String? logPath(String stepId);

  /// The file of the document [documentId]; `null` while it is not known,
  /// and for a storage without files.
  String? documentPath(String sessionId, String documentId);
}

/// The files of the filesystem storage, as [reader] reads them.
final class ReaderFiles implements StepFiles {
  ReaderFiles(this._reader);

  final FsReader _reader;

  @override
  Stream<String> stepLog(String sessionId, String stepId) =>
      _reader.stepLog(sessionId, stepId);

  @override
  Future<Object?> documentValue(String sessionId, String documentId) =>
      _reader.documentValue(sessionId, documentId);

  @override
  String? stepPath(String stepId) => _reader.stepPath(stepId);

  @override
  String? logPath(String stepId) => _reader.logPath(stepId);

  @override
  String? documentPath(String sessionId, String documentId) =>
      _reader.documentPath(sessionId, documentId);
}
