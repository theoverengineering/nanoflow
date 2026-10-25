import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'places.dart';

/// The `dart` that runs the tests; it runs a program from its source in its
/// own process, so a signal reaches the program itself.
final String dart = Platform.resolvedExecutable;

/// A program running as a process of its own: stdout read a line at a time,
/// stderr collected. Killed after the test if it still runs.
final class Program {
  Program._(this.process) {
    _lines = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    process.stderr.transform(utf8.decoder).listen(err.write);
    process.exitCode.then((_) => _exited = true).ignore();
    addTearDown(() {
      if (!_exited) process.kill(ProcessSignal.sigkill);
    });
  }

  /// Starts the fixture [name] with [arguments].
  static Future<Program> start(String name, List<String> arguments) async =>
      Program._(
        await Process.start(dart, [
          p.join('test', 'fixtures', '$name.dart'),
          ...arguments,
        ]),
      );

  final Process process;

  /// What it printed on stderr so far.
  final err = StringBuffer();

  late final StreamIterator<String> _lines;
  bool _exited = false;

  /// The next line it prints; fails the test when it ends before one, or
  /// prints none in 30 s.
  Future<String> line() async {
    final more = await _lines.moveNext().timeout(
      const Duration(seconds: 30),
      onTimeout: () => fail('printed no line in 30 s: $err'),
    );
    if (!more) fail('ended without printing a line: $err');
    return _lines.current;
  }

  /// Sends [command] as a line to its stdin, and gives the line it answers.
  Future<String> ask(String command) {
    process.stdin.writeln(command);
    return line();
  }

  /// Kills it with SIGKILL and waits until it is gone.
  Future<void> kill() async {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
  }

  /// The code it exits with.
  Future<int> get exitCode => process.exitCode.timeout(
    const Duration(seconds: 30),
    onTimeout: () => fail('has not exited: $err'),
  );
}

/// A process that owns a session of [place] (fixtures/hold.dart): a new one,
/// or the session [open].
Future<({Program program, String sessionId})> hold(
  Place place, {
  String? open,
}) async {
  final program = await Program.start('hold', [
    place,
    if (open == null) 'create' else ...['open', open],
  ]);
  return (program: program, sessionId: await program.line());
}

/// The feed of a reader, collected as it comes until the test ends.
final class Feed {
  Feed(this.reader) {
    final subscription = reader.changes().listen(
      changes.add,
      onError: errors.add,
    );
    addTearDown(subscription.cancel);
  }

  final SessionReader reader;

  /// Every change given so far, in order.
  final List<Change> changes = [];

  /// Every error given so far.
  final List<Object> errors = [];

  /// The changes of the session [sessionId] given so far, in order.
  List<Change> of(String sessionId) => [
    for (final change in changes)
      if (sessionIdOf(change) == sessionId) change,
  ];

  /// Waits until the feed has given a change of the session [sessionId] that
  /// [matches]; fails the test, saying it waited for [what], with what the
  /// feed gave of that session, when it has not after 20 s.
  Future<void> given(
    String sessionId,
    String what,
    bool Function(Change change) matches,
  ) async {
    final waited = Stopwatch()..start();
    while (!of(sessionId).any(matches)) {
      if (waited.elapsed > const Duration(seconds: 20)) {
        fail(
          'the feed has not given $what; of the session $sessionId it gave '
          '${of(sessionId)}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  /// Waits until the feed has given nothing new for 300 ms — many reads of a
  /// reader that looks every 20 ms.
  Future<void> settle() async {
    var given = -1;
    var quiet = Duration.zero;
    const tick = Duration(milliseconds: 50);
    while (quiet < const Duration(milliseconds: 300)) {
      await Future<void>.delayed(tick);
      final now = changes.length + errors.length;
      quiet = now == given ? quiet + tick : Duration.zero;
      given = now;
    }
  }
}

/// The id of the session [change] is of.
String sessionIdOf(Change change) => switch (change) {
  SessionAdded(:final session) => session.id,
  EffectAdded(:final effect) ||
  EffectChanged(:final effect) => effect.sessionId,
  EventAdded(:final sessionId) ||
  DocumentAdded(:final sessionId) ||
  LogCorrupted(:final sessionId) ||
  OwnerChanged(:final sessionId) => sessionId,
};

/// The events [changes] give, in order.
List<Event> eventsIn(List<Change> changes) => [
  for (final change in changes)
    if (change case EventAdded(:final event)) event,
];

/// Waits until [condition] holds; after 20 s fails the test, saying it
/// waited for [what].
Future<void> waitFor(String what, bool Function() condition) async {
  for (var i = 0; i < 400; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('timed out waiting for $what');
}
