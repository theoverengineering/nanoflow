// The data that flows along a run (D7): the document each step is given,
// and the document the run carries on after it. Documents are named by id.

import 'dart:convert';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';

/// The document a run carries into its first step, [first]: the step's
/// input, or else, for a run a split created, [fromParent], the document
/// its parent carried at the split.
String? carriedAtStart(Step first, {String? fromParent}) =>
    first.inputId ?? fromParent;

/// The input of a step of [node] when the run carries [carried]: the
/// carried document if the node declares `in`, none otherwise.
String? inputIdOf(Node node, String? carried) =>
    node.input == null ? null : carried;

/// The document a run carries on after a step of [node] that output
/// [outputId]: a worker's output, which is none for a worker without `out`;
/// a fork passes [carried] on unchanged.
String? carriedAfter(
  Node node, {
  required String? carried,
  required String? outputId,
}) => switch (node) {
  WorkerNode() => outputId,
  ForkNode() => carried,
};

/// The line `--call` gets on stdin for [step], without its `\n`: the value of
/// the step's input as one line of JSON, or nothing for a step without
/// input.
Future<String> inputLine(SessionHandle store, Step step) async {
  final inputId = step.inputId;
  if (inputId == null) return '';
  return jsonEncode(await store.documentValue(inputId));
}
