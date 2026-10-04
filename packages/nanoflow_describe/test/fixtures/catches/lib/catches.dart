// Which throws a catch takes on after its try: only those the first catch
// clause that surely fits them takes, and only when its block can finish
// normally. A catch that rethrows lets the throw go on out; one that returns
// leaves the function; one whose type the throw does not fit is passed by.
// And a caught throw goes on through the same finally as the normal ways out
// of the try, also from a closure called in place and from a ?: arm.
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';

Future<void> upload(Flow f, String file) async {
  try {
    final ok = await f.effect('check', () => file.isNotEmpty);
    if (!ok) throw StateError('nothing to upload');
    await f.effect('send', () => print('send $file'));
  } catch (e) {
    print('upload failed: $e');
    rethrow;
  }
  await f.effect('confirm', () => print('uploaded $file'));
}

Future<void> backup(Flow f, String disk) async {
  try {
    final free = await f.effect('measure', () => disk.length);
    if (free == 0) throw StateError('$disk is full');
    await f.effect('copy', () => print('copy to $disk'));
  } catch (e) {
    print('backup skipped: $e');
    return;
  }
  await f.effect('verify', () => print('verify $disk'));
}

Future<void> fetch(Flow f, String url) async {
  try {
    final page = await f.effect('download', () => url);
    if (page.isEmpty) throw StateError('empty page');
    if (page == 'busy') throw HttpException('try later');
    await f.effect('parse', () => print('parse $page'));
  } on HttpException catch (e) {
    print('fetch failed: $e');
  }
  await f.effect('store', () => print('store $url'));
}

Future<void> deploy(Flow f, String target) async {
  try {
    final ready = await f.effect('prepare', () => target.isNotEmpty);
    if (!ready) throw const FormatException('no target');
    await f.effect('ship', () => print('ship to $target'));
  } on Exception catch (e) {
    print('deploy failed: $e');
  } finally {
    await f.effect('unlock', () => print('unlock $target'));
  }
  await f.effect('announce', () => print('deployed $target'));
}

Future<void> rotate(Flow f, String key) async {
  try {
    await () async {
      final old = await f.effect('read', () => key);
      if (old.isEmpty) throw StateError('no key');
      await f.effect('replace', () => print('replace $old'));
    }();
  } catch (e) {
    print('rotate failed: $e');
  }
  await f.effect('audit', () => print('audit $key'));
}

Future<void> convert(Flow f, String unit) async {
  try {
    final factor = unit == 'km'
        ? await f.effect('scale', () => 1000)
        : throw ArgumentError.value(unit, 'unit');
    await f.effect('apply', () => print('x$factor'));
  } on ArgumentError catch (e) {
    print('convert failed: $e');
  }
  await f.effect('report', () => print('converted $unit'));
}

Future<void> importAll(Flow f, List<String> names) async {
  for (final name in names) {
    try {
      if (name.isEmpty) throw StateError('a name is empty');
    } catch (e) {
      print('cannot import: $e');
      rethrow;
    }
  }
  await f.effect('import', () => print('import ${names.length}'));
}
