// Who this process is, for the sessions it owns: its pid and the time the OS
// says it started, which together tell it from any other process, even one
// that gets its pid later (design §1, decision 4).

import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_process/nanoflow_process.dart';

/// This process as the owner of a session: its pid, and the start time the
/// OS of this machine gives for it; `null` there when the adapter of the OS
/// cannot tell.
///
/// Worked out once per process, on first use: a process neither changes its
/// pid nor starts again. The library gives it to the store, which only
/// writes it.
Owner currentOwner() => _owner;

/// What [currentOwner] gives; a top-level variable is set on first use.
final Owner _owner = _ownerOfThisProcess();

Owner _ownerOfThisProcess() {
  final processes = Processes.forPlatform();
  try {
    return Owner(pid: pid, started: processes.startOf(pid));
  } finally {
    // The adapter asks the OS and watches nothing here; nothing is left to
    // wait for, and a failure to say so does not matter.
    processes.close().ignore();
  }
}
