// Corners of the extraction: a switch on a record of types a switch must
// cover, which needs no default, beside one on a record that does; a
// Future.wait whose list comes after a named argument; methods of the same
// name in two unnamed extensions.
import 'package:nanoflow/nanoflow.dart';

enum Speed { slow, fast }

Future<void> route(Flow f, bool urgent, Speed speed, bool quiet) async {
  switch ((urgent, (speed, quiet))) {
    case (true, _):
      await f.effect('page', () => print('page'));
    case (false, (Speed.slow, _)):
      await f.effect('mail', () => print('mail'));
    case (false, (Speed.fast, true)):
      await f.effect('log', () => print('log'));
    case (false, (Speed.fast, false)):
      await f.effect('chat', () => print('chat'));
  }
}

Future<void> retry(Flow f, bool urgent, int tries) async {
  switch ((urgent, tries)) {
    case (true, _):
      await f.effect('now', () => print('now'));
    case (false, 0):
      await f.effect('later', () => print('later'));
  }
}

Future<void> ship(Flow f, List<String> targets) async {
  await Future.wait(eagerError: true, [
    f.effect('build', () => print('build')),
    f.effect('test', () => print('test')),
  ]);
  await Future.wait(
    eagerError: true,
    targets.map((target) async {
      await f.effect('upload', () => print('upload $target'));
    }),
  );
}

extension on Flow {
  Future<void> announce(String text) => effect('announce', () => print(text));
}

extension on String {
  Future<void> announce(Flow f) => f.effect('shout', () => print(this));
}

Future<void> announceBoth(Flow f, String text) async {
  await f.announce(text);
  await text.announce(f);
}
