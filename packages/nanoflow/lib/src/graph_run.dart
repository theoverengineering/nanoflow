// Runs a graph's shape in the session it is called in (graph design §6–§8).

import 'flow.dart';
import 'graph.dart';

/// Runs [shape] with [input] in the session of [flow] this is called in;
/// gives the output that went nowhere last, `null` when none did.
Future<Object?> runGraph(GraphShape shape, Flow flow, Object? input) =>
    throw UnimplementedError('graphs run from Task 3 of the plan on');
