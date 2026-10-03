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
    final ok = await f.step('check', () => file.isNotEmpty);
    if (!ok) throw StateError('nothing to upload');
    await f.step('send', () => print('send $file'));
  } catch (e) {
    print('upload failed: $e');
    rethrow;
  }
  await f.step('confirm', () => print('uploaded $file'));
}

Future<void> backup(Flow f, String disk) async {
  try {
    final free = await f.step('measure', () => disk.length);
    if (free == 0) throw StateError('$disk is full');
    await f.step('copy', () => print('copy to $disk'));
  } catch (e) {
    print('backup skipped: $e');
    return;
  }
  await f.step('verify', () => print('verify $disk'));
}

Future<void> fetch(Flow f, String url) async {
  try {
    final page = await f.step('download', () => url);
    if (page.isEmpty) throw StateError('empty page');
    if (page == 'busy') throw HttpException('try later');
    await f.step('parse', () => print('parse $page'));
  } on HttpException catch (e) {
    print('fetch failed: $e');
  }
  await f.step('store', () => print('store $url'));
}

Future<void> deploy(Flow f, String target) async {
  try {
    final ready = await f.step('prepare', () => target.isNotEmpty);
    if (!ready) throw const FormatException('no target');
    await f.step('ship', () => print('ship to $target'));
  } on Exception catch (e) {
    print('deploy failed: $e');
  } finally {
    await f.step('unlock', () => print('unlock $target'));
  }
  await f.step('announce', () => print('deployed $target'));
}

Future<void> rotate(Flow f, String key) async {
  try {
    await () async {
      final old = await f.step('read', () => key);
      if (old.isEmpty) throw StateError('no key');
      await f.step('replace', () => print('replace $old'));
    }();
  } catch (e) {
    print('rotate failed: $e');
  }
  await f.step('audit', () => print('audit $key'));
}

Future<void> convert(Flow f, String unit) async {
  try {
    final factor = unit == 'km'
        ? await f.step('scale', () => 1000)
        : throw ArgumentError.value(unit, 'unit');
    await f.step('apply', () => print('x$factor'));
  } on ArgumentError catch (e) {
    print('convert failed: $e');
  }
  await f.step('report', () => print('converted $unit'));
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
  await f.step('import', () => print('import ${names.length}'));
}
