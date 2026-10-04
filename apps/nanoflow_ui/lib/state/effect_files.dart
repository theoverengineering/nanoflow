import 'package:nanoflow_reader/nanoflow_reader.dart';

/// What the details of an effect read from the storage, on request: the
/// effect's log as it grows, the values of its documents, and the files they
/// are in (docs/ui-spec.md «Logs», «Окно деталей эффекта»).
abstract interface class EffectFiles {
  /// The log of the effect [effectId] of the session [sessionId]: the text
  /// written so far, then what is appended, until cancelled.
  Stream<String> effectLog(String sessionId, String effectId);

  /// The value of the document [documentId].
  Future<Object?> documentValue(String sessionId, String documentId);

  /// The directory of the effect [effectId]; `null` while it is not known, and
  /// for a storage without files.
  String? effectPath(String effectId);

  /// The file of the effect [effectId]'s log; `null` while it is not known, and
  /// for a storage without files.
  String? logPath(String effectId);

  /// The file of the document [documentId]; `null` while it is not known,
  /// and for a storage without files.
  String? documentPath(String sessionId, String documentId);
}

/// The files of the filesystem storage, as [reader] reads them.
final class ReaderFiles implements EffectFiles {
  ReaderFiles(this._reader);

  final FsReader _reader;

  @override
  Stream<String> effectLog(String sessionId, String effectId) =>
      _reader.effectLog(sessionId, effectId);

  @override
  Future<Object?> documentValue(String sessionId, String documentId) =>
      _reader.documentValue(sessionId, documentId);

  @override
  String? effectPath(String effectId) => _reader.effectPath(effectId);

  @override
  String? logPath(String effectId) => _reader.logPath(effectId);

  @override
  String? documentPath(String sessionId, String documentId) =>
      _reader.documentPath(sessionId, documentId);
}
