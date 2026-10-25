/// A value that a session keeps — the input of a workflow, the result of a
/// workflow or of an effect — does not come back from JSON as the type the code
/// declares: it is not JSON and has no `toJson`, its type is neither a JSON
/// type nor one with a codec (`Flow.addCodec`), or the codec's `fromJson`
/// fails.
///
/// For an effect that runs it is the effect's exception: the effect fails with
/// it. For an effect's saved result, whose type has no codec when `Flow.resume`
/// takes the session on, it ends the session as a [StorageException] does.
final class CodecException implements Exception {
  const CodecException(this.type, this.reason);

  /// The type of the value, as the workflow or the effect declares it.
  final Type type;

  /// What went wrong.
  final String reason;

  @override
  String toString() => 'CodecException: $type: $reason';
}

/// `Flow.resume` was asked for a session that the store does not have.
final class SessionNotFoundException implements Exception {
  const SessionNotFoundException(this.sessionId);

  final String sessionId;

  @override
  String toString() =>
      'SessionNotFoundException: there is no session $sessionId';
}

/// `Flow.resume` was given another workflow than the one whose call the
/// session is.
final class WorkflowMismatchException implements Exception {
  const WorkflowMismatchException(this.sessionId, this.expected, this.actual);

  final String sessionId;

  /// The name of the session's workflow.
  final String expected;

  /// The name of the workflow given.
  final String actual;

  @override
  String toString() =>
      'WorkflowMismatchException: the session $sessionId is a call of '
      '$expected, not of $actual';
}

/// A session could not be written or read.
///
/// A session whose store fails as it runs ends there: no effect starts in it
/// any more, nothing more is written to it, and its result is this
/// exception.
final class StorageException implements Exception {
  const StorageException(this.cause);

  /// What the store threw: of the files of `runs/`, a `FileSystemException`,
  /// a `StoreCorruptedException`, or a `FormatException` for a file that is
  /// not the JSON it should be; of another store, what it throws.
  final Object cause;

  @override
  String toString() => 'StorageException: $cause';
}

/// The flow was stopped: no effect starts, no program starts with `exec` in
/// its sessions, and no session starts or resumes any more.
final class FlowStoppedException implements Exception {
  const FlowStoppedException();

  @override
  String toString() => 'FlowStoppedException: the flow was stopped';
}

/// The session that `Flow.resume` was asked for had failed: its workflow
/// threw. The result of the session is this exception, with the stack trace
/// the session keeps.
final class SessionFailedException implements Exception {
  const SessionFailedException(this.sessionId, this.error);

  final String sessionId;

  /// What the workflow threw, as the session keeps it: its text on one line.
  final String error;

  @override
  String toString() =>
      'SessionFailedException: the session $sessionId failed: $error';
}
