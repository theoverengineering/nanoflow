import 'dart:io';

import 'mac_processes.dart';
import 'unsupported_processes.dart';

/// What the OS knows of a process: when it started and when it is gone.
///
/// A process is known by its pid and its start time: a pid alone is not
/// unique, as the OS gives the number of a dead process to another one. Each
/// OS has an adapter of its own; a new OS needs only a new adapter.
abstract interface class Processes {
  /// The adapter of this OS: [MacProcesses] on macOS, else
  /// [UnsupportedProcesses].
  factory Processes.forPlatform() =>
      Platform.isMacOS ? MacProcesses() : UnsupportedProcesses();

  /// Whether the adapter can tell the start and the exit of processes.
  bool get supported;

  /// The time the process [pid] started, by the OS, in UTC, truncated to
  /// milliseconds; `null` when there is no such process or the adapter
  /// cannot tell.
  DateTime? startOf(int pid);

  /// Completes when the process [pid] is gone: at once when it is gone
  /// already.
  ///
  /// Never completes with an adapter that is not [supported].
  Future<void> exitOf(int pid);

  /// Stops watching: the pending [exitOf] futures, and later ones, never
  /// complete.
  Future<void> close();
}
