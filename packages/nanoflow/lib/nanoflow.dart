/// Workflows as ordinary Dart functions that run in the process of the app:
/// [Flow] runs them as sessions written to `runs/`, every effect of which gets
/// a key that finds it again, its result kept as JSON and its output in its
/// log; [exec] runs an external program, which belongs to the effect or the
/// session that runs it and dies with the process. A [Graph] of nodes is the
/// other way to write a workflow: each [node] a unit of work that runs as one
/// effect, the graph's routes saying what follows what.
library;

export 'package:nanoflow_store/nanoflow_store.dart' show SessionBusyException;

export 'src/errors.dart'
    show
        CodecException,
        FlowStoppedException,
        SessionFailedException,
        SessionNotFoundException,
        StorageException,
        WorkflowMismatchException;
export 'src/exec.dart' show ExecException, exec;
export 'src/flow.dart' show Flow, FlowSession;
export 'src/graph.dart' show Graph, Next, Node, Part, node;
