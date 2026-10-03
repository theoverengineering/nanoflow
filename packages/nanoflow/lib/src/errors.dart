/// A value that a session keeps — the input of a workflow, the result of a
/// workflow or of a step — cannot be turned into JSON.
///
/// For a step it is the step's exception: the step fails with it.
final class CodecException implements Exception {
  const CodecException(this.type, this.reason);

  /// The type of the value, as the workflow or the step declares it.
  final Type type;

  /// What went wrong.
  final String reason;

  @override
  String toString() => 'CodecException: $type: $reason';
}
