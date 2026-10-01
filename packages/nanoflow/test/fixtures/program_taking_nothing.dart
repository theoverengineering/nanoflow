// A graph program whose start node takes no input.
import 'package:nanoflow/nanoflow.dart';

final tick = node((Object? _) async {});

final graph = Graph.start(tick);

void main(List<String> args) => serve(args, graph);
