// What a throw does to a graph: a catch takes it on after the try, through a
// finally too; a throw in a catch clause, which is not drawn, draws nothing;
// a throw arm of a switch expression or of ?: ends its path. And a finally
// drawn once per way out of its try warns once.
import 'package:nanoflow/nanoflow.dart';

Future<void> cleanUp(Flow f, String lock, bool early) async {
  try {
    await f.step('acquire', () => print('acquire $lock'));
    if (early) return;
    await f.step('use', () => print('use $lock'));
  } finally {
    await f.step('release-$lock', () => print('release $lock'));
  }
}

Future<void> importLines(Flow f, List<String> lines) async {
  for (final line in lines) {
    try {
      int.parse(line);
    } catch (e) {
      throw StateError('bad line $line');
    }
  }
  await f.step('import', () => print('import ${lines.length} lines'));
}

Future<void> sync(Flow f, String remote) async {
  try {
    final reachable = await f.step('ping', () => remote.isNotEmpty);
    if (!reachable) throw StateError('$remote is down');
    await f.step('pull', () => print('pull $remote'));
  } catch (e) {
    print('sync failed: $e');
  }
  await f.step('log', () => print('synced $remote'));
}

Future<void> mirror(Flow f, String source) async {
  try {
    try {
      final ok = await f.step('fetch', () => source.isNotEmpty);
      if (!ok) throw StateError('cannot fetch $source');
      await f.step('write', () => print('write $source'));
    } finally {
      await f.step('close', () => print('close $source'));
    }
  } catch (e) {
    print('mirror failed: $e');
  }
  await f.step('report', () => print('mirrored $source'));
}

Future<void> measure(Flow f, String kind) async {
  final size = switch (kind) {
    'disk' => await f.step('stat', () => 100),
    _ => throw ArgumentError.value(kind, 'kind'),
  };
  final unit = size > 50
      ? await f.step('unit', () => 'GB')
      : throw StateError('$size is too small');
  await f.step('record', () => print('$size $unit'));
}
