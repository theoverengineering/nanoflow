// serve calls the compiler must reject; the markers are those of
// graph_shapes.dart.
import 'package:nanoflow/nanoflow.dart';

final length = node((String s) => s.length);
final graph = Graph.start(length);

// The same call, written correctly: input gives what the start node takes.
final ok = serve([], graph, input: (raw) => raw.trim());

// An input function that gives another type than the start node takes.
final wrong = serve([], graph, input: int.parse); // error: could_not_infer
