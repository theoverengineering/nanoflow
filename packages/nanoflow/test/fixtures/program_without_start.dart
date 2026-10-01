// A graph program whose graph does not build: it has no Graph.start, and
// `length` declares its next twice.
import 'package:nanoflow/nanoflow.dart';

final length = node((String s) async => s.length);
final half = node((int n) async => n ~/ 2);

final graph = Graph([
  Graph.part(length).next(half),
  Graph.part(length).next(half),
]);

void main(List<String> args) => serve(args, graph);
