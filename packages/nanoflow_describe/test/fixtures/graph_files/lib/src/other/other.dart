// Two graphs of one file that call nothing; one of them warns.
import 'package:nanoflow/nanoflow.dart';

import '../nodes.dart';

final other = Graph<String, String>('other', [Graph.start(survey)]);

final another = Graph<String, int>('another', [
  Graph.start(rank).next((size) => DateTime.now().isUtc ? null : null),
]);
