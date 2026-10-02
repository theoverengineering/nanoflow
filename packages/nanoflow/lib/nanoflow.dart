/// The nanoflow library is being rewritten as in-process workflows; for now it
/// gives only [exec], which runs an external program.
library;

export 'src/exec.dart' show ExecException, exec;
