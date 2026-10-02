// A graph program whose data classes declare toJson abstract, as a sealed
// hierarchy and a freezed 3 model do: test/build_test.dart describes its
// graph, test/serve_test.dart calls its nodes.
import 'package:nanoflow/nanoflow.dart';

/// A sealed hierarchy: the base decodes, each subclass encodes itself.
sealed class Outcome {
  const Outcome();

  factory Outcome.fromJson(Map<String, Object?> json) => switch (json) {
    {'kind': 'passed', 'count': final int count} => Passed(count),
    {'kind': 'failed', 'reason': final String reason} => Failed(reason),
    _ => throw FormatException('not an outcome: $json'),
  };

  Map<String, Object?> toJson();
}

final class Passed extends Outcome {
  const Passed(this.count);

  final int count;

  @override
  Map<String, Object?> toJson() => {'kind': 'passed', 'count': count};
}

final class Failed extends Outcome {
  const Failed(this.reason);

  final String reason;

  @override
  Map<String, Object?> toJson() => {'kind': 'failed', 'reason': reason};
}

/// The shape freezed 3 gives `@freezed abstract class Summary with
/// _$Summary`: toJson is abstract in the generated mixin, and the generated
/// class that implements Summary implements it.
abstract class Summary with _$Summary {
  const factory Summary({required String text}) = _Summary;

  factory Summary.fromJson(Map<String, dynamic> json) =>
      _Summary.fromJson(json);
}

mixin _$Summary {
  String get text;

  Map<String, dynamic> toJson();
}

class _Summary implements Summary {
  const _Summary({required this.text});

  factory _Summary.fromJson(Map<String, dynamic> json) =>
      _Summary(text: json['text'] as String);

  @override
  final String text;

  @override
  Map<String, dynamic> toJson() => {'text': text};
}

final judge = node(
  (int count) async => count > 0 ? Passed(count) : Failed('no tests'),
);
final summarize = node(
  (Outcome o) async => Summary(
    text: switch (o) {
      Passed(:final count) => '$count passed',
      Failed(:final reason) => 'failed: $reason',
    },
  ),
);
final shout = node((Summary s) async => s.text.toUpperCase());

final graph = Graph.start(judge).next(summarize).next(shout);

void main(List<String> args) => serve(args, graph);
