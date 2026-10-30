// Nodes with a limit of effects at once: a literal one goes to the graph
// file; one that is not a literal is warned of and left out.
import 'package:nanoflow/nanoflow.dart';

const two = 2;

final heavy = node('heavy', (int x) async => x, concurrency: 4);
final light = node('light', (int x) async => x);
final counted = node('counted', (int x) async => x, concurrency: two);

final limited = Graph<int, int>('limited', [
  Graph.start(heavy).next((x) => light(x)),
  Graph.part(light).next((x) => counted(x)),
]);
