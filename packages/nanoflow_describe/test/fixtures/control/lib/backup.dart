// The rest of the control flow a graph draws: a switch on a sealed class, one
// with a default and one with a catch-all case, a switch expression, an
// if-case, while with a condition and do-while, for(;;) with continue and
// break, ?: with && and ||, try with finally (also left by return, break and
// continue), a throw, a record's wait; and what it leaves out: a loop without
// effects and a fork that decides nothing.
import 'package:nanoflow/nanoflow.dart';

sealed class Target {}

final class Disk extends Target {
  Disk(this.path);
  final String path;
}

final class Bucket extends Target {
  Bucket(this.name);
  final String name;
}

Future<void> store(Flow f, Target target) async {
  switch (target) {
    case Disk(:final path):
      await f.effect('copy', () => print('copy to $path'));
    case Bucket(:final name):
      await f.effect('upload', () => print('upload to $name'));
  }
}

Future<void> compress(Flow f, String format) async {
  switch (format) {
    case 'zip':
      await f.effect('zip', () => print('zip'));
    case 'tar':
      await f.effect('tar', () => print('tar'));
  }
  await f.effect('checksum', () => print('checksum'));
}

Future<void> schedule(Flow f, Map<String, Object?> config) async {
  if (config case {'every': final int hours}) {
    await f.effect('schedule', () => print('every $hours h'));
  }
}

Future<void> waitForHost(Flow f, String host) async {
  var tries = 0;
  while (tries < 3) {
    final up = await f.effect('is-up', () => tries > 1);
    if (up) break;
    tries++;
  }
  bool busy;
  do {
    await f.effect('ping', () => print('ping $host'));
    busy = await f.effect('is-busy', () => false);
  } while (busy);
}

Future<void> sendParts(Flow f, List<String> parts) async {
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].isEmpty) continue;
    final sent = await f.effect('send', () => parts[i].length < 100);
    if (!sent) break;
  }
  await f.effect('close', () => print('closed'));
}

Future<void> report(Flow f, bool quiet, bool urgent) async {
  final text = quiet ? '' : await f.effect('summarize', () => 'summary');
  if (urgent || text.isNotEmpty && await f.effect('ask', () => true)) {
    await f.effect('mail', () => print(text));
  }
}

Future<void> rotate(Flow f, List<String> files) async {
  var size = 0;
  for (final file in files) {
    size += file.length;
  }
  // Nothing to rotate when every file is packed already.
  if (files.every(
    (file) =>
        file.endsWith('.gz') || file.endsWith('.zip') || file.endsWith('.xz'),
  )) {
    return;
  }
  try {
    await f.effect('lock', () => print('lock'));
  } finally {
    await f.effect('unlock', () => print('unlock'));
  }
  if (size < 100) return;
  print('rotated $size bytes');
}

Future<void> verify(Flow f, Target target) async {
  final ok = switch (target) {
    Disk(:final path) => await f.effect('stat', () => path.isNotEmpty),
    Bucket() => await f.effect('head', () => true),
  };
  await f.effect('record', () => print('verified: $ok'));
}

Future<void> deployLocked(Flow f, bool early) async {
  try {
    await f.effect('lock', () => print('lock'));
    if (early) return;
    await f.effect('work', () => print('work'));
  } finally {
    await f.effect('unlock', () => print('unlock'));
  }
  await f.effect('report', () => print('deployed'));
}

Future<void> drain(Flow f, List<String> queues) async {
  for (final queue in queues) {
    try {
      final size = await f.effect('measure', () => queue.length);
      if (size == 0) continue;
      if (size > 100) break;
      await f.effect('process', () => print('process $queue'));
    } finally {
      await f.effect('release', () => print('release $queue'));
    }
  }
  await f.effect('done', () => print('drained'));
}

Future<void> alert(Flow f, String level) async {
  switch (level) {
    case 'error':
      await f.effect('page', () => print('page the on-call'));
    case _:
      await f.effect('log', () => print('log $level'));
  }
}

Future<void> restore(Flow f, String snapshot) async {
  final found = await f.effect('find', () => snapshot.isNotEmpty);
  if (!found) throw StateError('no snapshot $snapshot');
  await f.effect('restore', () => print('restore $snapshot'));
}

Future<void> prepare(Flow f, String host) async {
  final (disk, memory) = await (
    f.effect('measure-disk', () => 100),
    f.effect('measure-memory', () => 8),
  ).wait;
  await f.effect('plan', () => print('$host: $disk GB, $memory GB'));
}
