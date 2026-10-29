import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_ui/state/call_runs.dart';
import 'package:nanoflow_ui/state/effect_places.dart';
import 'package:nanoflow_ui/state/session_feed.dart';

import 'support.dart';

void main() {
  final file = packagesGraphFile();
  final inPlace = file.functions['lib/packages.dart#inPlace']!;
  final places = EffectPlaces.of(inPlace, file.functions);
  // inPlace's call of ship(): upload, verify, tag.
  final ship = places.within(inPlace.body.node('2')!);

  /// The names of the effects of each run of ship() in [session], by the id
  /// of its first effect.
  Map<String, List<String>> runsOf(SessionData session) => {
    for (final MapEntry(key: first, value: run) in chainsIn(
      ship,
      places: places,
      session: session,
    ).entries)
      first: [for (final effect in run) session.effects[effect.effectId]!.name],
  };

  test('a run is a chain of the effects in the call by after, begun by one '
      'that follows an effect outside it', () {
    final j = Journal('a1b2-session', workflow: 'inPlace')
      ..effect('plan', 1, end: 2, place: packagesAt(4), key: 'p', after: null)
      ..effect('upload', 3, end: 4, place: packagesAt(7), key: 'uc', after: 'p')
      ..effect('upload', 3, end: 5, place: packagesAt(7), key: 'ut', after: 'p')
      ..effect(
        'verify',
        6,
        end: 7,
        place: packagesAt(8),
        key: 'vc',
        after: 'uc',
      )
      ..effect('verify', 8, place: packagesAt(8), key: 'vt', after: 'ut');
    expect(runsOf(j.data), {
      j.effects[1].id: ['upload', 'verify'],
      j.effects[2].id: ['upload', 'verify'],
    });
  });

  test('an effect rerun after another effect than before follows its record '
      'as it is now, whenever that effect started', () {
    final j = Journal('a1b2-session', workflow: 'inPlace')
      ..effect(
        'verify-core',
        3,
        end: 4,
        place: packagesAt(8),
        key: 'verify#1@core',
        // The rerun rewrote it: it follows tool's upload now.
        after: 'upload#2@c',
      )
      ..effect(
        'upload-core',
        1,
        end: 2,
        place: packagesAt(7),
        key: 'upload#1@c',
        after: null,
      )
      ..effect(
        'upload-tool',
        5,
        end: 6,
        place: packagesAt(7),
        key: 'upload#2@c',
        after: null,
      );
    expect(
      runsOf(j.data).values,
      unorderedEquals([
        ['upload-core'],
        ['verify-core', 'upload-tool'],
      ]),
    );
  });

  test('an effect whose predecessor has no record yet begins a run', () {
    final j = Journal('a1b2-session', workflow: 'inPlace')
      ..effect(
        'verify-core',
        1,
        place: packagesAt(8),
        key: 'verify#1@core',
        after: 'upload#1@c',
      );
    expect(runsOf(j.data), {
      j.effects.single.id: ['verify-core'],
    });
  });
}
