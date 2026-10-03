// The rest of the control flow a graph draws: a switch on a sealed class and
// one with a default, an if-case, while with a condition and do-while,
// for(;;) with continue and break, ?: with && and ||, try with finally; and
// what it leaves out: a loop without steps and a fork that decides nothing.
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
      await f.step('copy', () => print('copy to $path'));
    case Bucket(:final name):
      await f.step('upload', () => print('upload to $name'));
  }
}

Future<void> compress(Flow f, String format) async {
  switch (format) {
    case 'zip':
      await f.step('zip', () => print('zip'));
    case 'tar':
      await f.step('tar', () => print('tar'));
  }
  await f.step('checksum', () => print('checksum'));
}

Future<void> schedule(Flow f, Map<String, Object?> config) async {
  if (config case {'every': final int hours}) {
    await f.step('schedule', () => print('every $hours h'));
  }
}

Future<void> waitForHost(Flow f, String host) async {
  var tries = 0;
  while (tries < 3) {
    final up = await f.step('is-up', () => tries > 1);
    if (up) break;
    tries++;
  }
  bool busy;
  do {
    await f.step('ping', () => print('ping $host'));
    busy = await f.step('is-busy', () => false);
  } while (busy);
}

Future<void> sendParts(Flow f, List<String> parts) async {
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].isEmpty) continue;
    final sent = await f.step('send', () => parts[i].length < 100);
    if (!sent) break;
  }
  await f.step('close', () => print('closed'));
}

Future<void> report(Flow f, bool quiet, bool urgent) async {
  final text = quiet ? '' : await f.step('summarize', () => 'summary');
  if (urgent || text.isNotEmpty && await f.step('ask', () => true)) {
    await f.step('mail', () => print(text));
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
    await f.step('lock', () => print('lock'));
  } finally {
    await f.step('unlock', () => print('unlock'));
  }
  if (size < 100) return;
  print('rotated $size bytes');
}
