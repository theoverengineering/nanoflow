/// A nanoflow graph written in Dart: nodes are functions, the graph is
/// their arrows, and the types of the functions are the types of the data.
library;

export 'src/graph.dart' show Graph, IfPart, Part, SwitchPart, WorkerPart;
export 'src/vertex.dart'
    show AnyVertex, Accepts, Fork, Vertex, Worker, fork, node;
