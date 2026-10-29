// A graph other graphs call; its route warns.
import 'package:nanoflow/nanoflow.dart';

import '../nodes.dart';

/// Makes an idea shorter.
final compressIdea = Graph<String, String>('compressIdea', [
  Graph.start(shorten)
      .next((idea) => DateTime.now().isUtc ? polish(idea) : polish('$idea!')),
]);
