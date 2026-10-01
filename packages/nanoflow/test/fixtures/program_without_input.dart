// A graph program whose start node takes input but that gives serve no input
// function; test/serve_test.dart also copies and edits it for --watch.
import 'package:nanoflow/nanoflow.dart';

final length = node((String s) async => s.length);

final graph = Graph.start(length);

void main(List<String> args) => serve(args, graph);
