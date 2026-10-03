// The owner of a session told by the reader with the OS port of macOS: a
// child process owns the session, and is killed.
@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_process/nanoflow_process.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

/// How long the reader may take to tell that a killed owner is gone.
const exitWait = Duration(seconds: 5);

/// Starts a process that owns the session in [sessionDir], killed when the
/// test ends. Completes once it has written itself into `.owner.lock`;
/// fails, with what the process printed to stderr, when it ends without
/// saying so.
Future<Process> startOwner(String sessionDir) async {
  final owner = await Process.start(Platform.resolvedExecutable, [
    p.join('test', 'fixtures', 'own_session.dart'),
    sessionDir,
  ]);
  addTearDown(() {
    owner.kill(ProcessSignal.sigkill);
    return owner.exitCode;
  });
  final stderrText = owner.stderr.transform(utf8.decoder).join();
  final lines = await owner.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .take(1)
      .toList();
  if (lines.firstOrNull == 'owning') return owner;
  // Its stdout is closed: the process has ended, and its stderr ends too.
  final why = lines.isEmpty
      ? 'it ended without printing, stderr: ${await stderrText}'
      : 'it printed "${lines.single}"';
  fail('the process that should own the session did not report it: $why');
}

void main() {
  test('tells the owner alive while its process runs, and not alive within '
      'a few seconds of a SIGKILL', () async {
    final runsDir = await newRunsDir();
    final session = newSession();
    final sessionDir = writeSession(
      runsDir,
      session,
      events: [SessionStarted(time: at(0), code: null)],
    );
    final child = await startOwner(sessionDir);
    final processes = MacProcesses();
    addTearDown(processes.close);
    final owner = Owner(pid: child.pid, started: processes.startOf(child.pid));

    // The reader makes the adapter of this OS, and closes it when the feed is
    // cancelled at the end of the test. Nothing on disk changes after the
    // first read: only the exit can make it look again.
    final feed = Feed(runsDir, pollInterval: const Duration(hours: 1));
    expect(
      await feed.next<OwnerChanged>(),
      OwnerChanged(sessionId: session.id, owner: owner, alive: true),
    );

    child.kill(ProcessSignal.sigkill);

    expect(
      await feed
          .next<OwnerChanged>((change) => change.alive == false)
          .timeout(exitWait),
      OwnerChanged(sessionId: session.id, owner: owner, alive: false),
    );
    expect(feed.errors, isEmpty);
  });
}
