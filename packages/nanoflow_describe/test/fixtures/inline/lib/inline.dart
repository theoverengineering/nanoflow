// One body per package, run in copies side by side: written in place as an
// async closure called right there or given to map, or as a call; and the
// same body one package after another in an ordinary for.
import 'package:nanoflow/nanoflow.dart';

Future<void> inPlace(Flow f, List<String> packages) async {
  final results = await Future.wait([
    for (final pkg in packages)
      () async {
        final up = await f.effect('upload', () => '$pkg:uploaded');
        final ok = await f.effect('verify', () => '$up:verified');
        return f.effect('tag', () => '$ok:tagged');
      }(),
  ]);
  await f.effect('announce', () => results.join(' + '));
}

Future<void> viaMap(Flow f, List<String> packages) async {
  final results = await Future.wait(
    packages.map((pkg) async {
      final up = await f.effect('upload', () => '$pkg:uploaded');
      final ok = await f.effect('verify', () => '$up:verified');
      return f.effect('tag', () => '$ok:tagged');
    }),
  );
  await f.effect('announce', () => results.join(' + '));
}

Future<void> viaCall(Flow f, List<String> packages) async {
  final results = await Future.wait([
    for (final pkg in packages) publish(f, pkg),
  ]);
  await f.effect('announce', () => results.join(' + '));
}

Future<void> sequential(Flow f, List<String> packages) async {
  final results = <String>[];
  for (final pkg in packages) {
    final up = await f.effect('upload', () => '$pkg:uploaded');
    final ok = await f.effect('verify', () => '$up:verified');
    results.add(await f.effect('tag', () => '$ok:tagged'));
  }
  await f.effect('announce', () => results.join(' + '));
}

Future<String> publish(Flow f, String pkg) async {
  final up = await f.effect('upload', () => '$pkg:uploaded');
  final ok = await f.effect('verify', () => '$up:verified');
  return f.effect('tag', () => '$ok:tagged');
}
