// The body of publish() written in place, with no function: copies side by
// side as an async closure called right there or given to map, and one
// after another in an ordinary for.
import 'package:static_graph/flow.dart';

Future<void> inPlace(Flow f, List<String> packages) async {
  final results = await Future.wait([
    for (final pkg in packages)
      () async {
        final up = await f.step('upload', () => '$pkg:uploaded');
        final ok = await f.step('verify', () => '$up:verified');
        return f.step('tag', () => '$ok:tagged');
      }(),
  ]);
  await f.step('announce', () => results.join(' + '));
}

Future<void> viaMap(Flow f, List<String> packages) async {
  final results = await Future.wait(
    packages.map((pkg) async {
      final up = await f.step('upload', () => '$pkg:uploaded');
      final ok = await f.step('verify', () => '$up:verified');
      return f.step('tag', () => '$ok:tagged');
    }),
  );
  await f.step('announce', () => results.join(' + '));
}

Future<void> sequential(Flow f, List<String> packages) async {
  final results = <String>[];
  for (final pkg in packages) {
    final up = await f.step('upload', () => '$pkg:uploaded');
    final ok = await f.step('verify', () => '$up:verified');
    results.add(await f.step('tag', () => '$ok:tagged'));
  }
  await f.step('announce', () => results.join(' + '));
}
