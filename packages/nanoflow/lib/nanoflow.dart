/// Workflows as ordinary Dart functions that run in the process of the app:
/// [Flow] runs them as sessions written to `runs/`, every step of which gets
/// a key that finds it again; [exec] runs an external program.
library;

export 'src/errors.dart' show CodecException;
export 'src/exec.dart' show ExecException, exec;
export 'src/flow.dart' show Flow, FlowSession;
