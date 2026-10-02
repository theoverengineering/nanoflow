/// A nanoflow graph written in Dart: nodes are functions, the graph is
/// their arrows, and the types of the functions are the types of the data.
///
/// `main` hands the graph to [serve], which makes the file a graph program;
/// a node's function runs programs with [exec]. A test that imports the
/// graph checks that it builds with [graphErrors].
library;

export 'src/build.dart' show graphErrors;
export 'src/exec.dart' show ExecException, exec;
export 'src/graph.dart' show Graph, IfPart, Part, SwitchPart, WorkerPart;
export 'src/serve.dart' show serve;
export 'src/vertex.dart'
    show AnyVertex, Accepts, Fork, Vertex, Worker, fork, node;
