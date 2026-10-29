/// Workflows as graphs of nodes that run in the process of the app: a [Graph]
/// of [node]s, each a unit of work that runs as one effect, its routes
/// saying what follows what. [Flow] runs a graph as a session written to
/// `runs/`, every node of which gets a key that finds it again, its result
/// kept as JSON and its output in its log; [exec] runs an external program,
/// which belongs to the node or the session that runs it and dies with the
/// process.
library;

export 'package:nanoflow_model/nanoflow_model.dart'
    show SessionBusyException, SessionExistsException, SessionStore;

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
