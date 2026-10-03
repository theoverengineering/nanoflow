/// Workflows as ordinary Dart functions that run in the process of the app:
/// [Flow] runs them as sessions written to `runs/`, every step of which gets
/// a key that finds it again; [exec] runs an external program.
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
