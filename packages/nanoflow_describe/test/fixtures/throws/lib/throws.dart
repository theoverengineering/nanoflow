// What a throw does to a graph: a catch takes it on after the try, through a
// finally too; a throw in a catch clause, which is not drawn, draws nothing;
// a throw arm of a switch expression or of ?: ends its path. And a finally
// drawn once per way out of its try warns once.
import 'package:nanoflow/nanoflow.dart';

Future<void> cleanUp(Flow f, String lock, bool early) async {
  try {
    await f.effect('acquire', () => print('acquire $lock'));
    if (early) return;
    await f.effect('use', () => print('use $lock'));
  } finally {
    await f.effect('release-$lock', () => print('release $lock'));
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
  await f.effect('import', () => print('import ${lines.length} lines'));
}

Future<void> sync(Flow f, String remote) async {
  try {
    final reachable = await f.effect('ping', () => remote.isNotEmpty);
    if (!reachable) throw StateError('$remote is down');
    await f.effect('pull', () => print('pull $remote'));
  } catch (e) {
    print('sync failed: $e');
  }
  await f.effect('log', () => print('synced $remote'));
}

Future<void> mirror(Flow f, String source) async {
  try {
    try {
      final ok = await f.effect('fetch', () => source.isNotEmpty);
      if (!ok) throw StateError('cannot fetch $source');
      await f.effect('write', () => print('write $source'));
    } finally {
      await f.effect('close', () => print('close $source'));
    }
  } catch (e) {
    print('mirror failed: $e');
  }
  await f.effect('report', () => print('mirrored $source'));
}

Future<void> measure(Flow f, String kind) async {
  final size = switch (kind) {
    'disk' => await f.effect('stat', () => 100),
    _ => throw ArgumentError.value(kind, 'kind'),
  };
  final unit = size > 50
      ? await f.effect('unit', () => 'GB')
      : throw StateError('$size is too small');
  await f.effect('record', () => print('$size $unit'));
}
