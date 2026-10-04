import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/body_path.dart';
import 'package:nanoflow_ui/state/copies.dart';
import 'package:nanoflow_ui/state/effect_places.dart';
import 'package:nanoflow_ui/state/session_feed.dart';

import 'support.dart';

// The sessions are those the workflows of `copiesGraphJson` write: the keys
// and `after`s are as the library gives them (decision D1), shortened. A
// copy's effects follow one another in it; its first effect follows the effect
// before the copies, or none.

final file = copiesGraphFile();

EffectPlaces placesOf(String workflow) => EffectPlaces.of(
  file.functions['lib/copies.dart#$workflow'],
  file.functions,
);

CopiesNode copiesNode(String workflow, [String id = '1']) =>
    file.functions['lib/copies.dart#$workflow']!.body.node(id)! as CopiesNode;

/// The names of each copy's effects, by copy number.
Map<int, List<String>> namesOf(List<Copy> copies, SessionData session) => {
  for (final copy in copies)
    copy.number: [
      for (final effect in copy.effects) session.effects[effect.effectId]!.name,
    ],
};

/// The package of each copy, by number: the name of its first effect ends
/// with it (`upload-core`).
Map<int, String> packagesOf(List<Copy> copies) => {
  for (final copy in copies) copy.number: copy.first.effectId.split('-')[2],
};

/// `inPlace` over core, tool and cli: the copies start in that order, and
/// cli's upload ends first.
Journal inPlaceJournal() {
  final j = Journal('a1b2-session', workflow: 'inPlace');
  j.effect('plan', 1, end: 2, place: copiesAt(4), key: 'plan#1@r', after: null);
  for (final (i, pkg) in ['core', 'tool', 'cli'].indexed) {
    j.effect(
      'upload-$pkg',
      3 + i / 1000,
      end: 6 - i,
      output: 'out-$pkg',
      place: copiesAt(7),
      key: 'upload#${i + 1}@c',
      after: 'plan#1@r',
    );
  }
  for (final (i, pkg) in ['cli', 'tool', 'core'].indexed) {
    j.effect(
      'verify-$pkg',
      7 + i,
      end: 10 + i,
      place: copiesAt(8),
      key: 'verify#1@$pkg',
      after: 'upload#${3 - i}@c',
    );
    j.effect(
      'tag-$pkg',
      10 + i,
      end: 13 + i,
      place: copiesAt(9),
      key: 'tag#1@$pkg',
      after: 'verify#1@$pkg',
    );
  }
  j.effect(
    'announce',
    20,
    end: 21,
    place: copiesAt(12),
    key: 'announce#1@r',
    after: 'plan#1@r',
  );
  return j;
}

void main() {
  test('in place: a copy is a chain of effects in the frame by after; plan and '
      'announce are in none', () {
    final session = inPlaceJournal().data;
    final copies = copiesOf(
      copiesNode('inPlace', '2'),
      places: placesOf('inPlace'),
      session: session,
    );
    expect(packagesOf(copies), {1: 'core', 2: 'tool', 3: 'cli'});
    expect(namesOf(copies, session), {
      1: ['upload-core', 'verify-core', 'tag-core'],
      2: ['upload-tool', 'verify-tool', 'tag-tool'],
      3: ['upload-cli', 'verify-cli', 'tag-cli'],
    });
    expect(
      copies.map((copy) => copy.status),
      everyElement(CopyStatus.finished),
    );
  });

  test('given to map: the first effects follow no effect', () {
    final j = Journal('c3d4-session', workflow: 'inPlace');
    for (final (i, pkg) in ['core', 'tool'].indexed) {
      j.effect(
        'upload-$pkg',
        1 + i,
        end: 3,
        place: copiesAt(7),
        key: 'upload#${i + 1}@r',
        after: null,
      );
    }
    for (final (i, pkg) in ['tool', 'core'].indexed) {
      j.effect(
        'verify-$pkg',
        4 + i,
        end: 6,
        place: copiesAt(8),
        key: 'verify#1@$pkg',
        after: 'upload#${2 - i}@r',
      );
    }
    final session = j.data;
    final copies = copiesOf(
      copiesNode('inPlace', '2'),
      places: placesOf('inPlace'),
      session: session,
    );
    expect(namesOf(copies, session), {
      1: ['upload-core', 'verify-core'],
      2: ['upload-tool', 'verify-tool'],
    });
  });

  test('through a call: the effects of the function called in the frame are '
      'in it', () {
    final j = Journal('e5f6-session', workflow: 'viaCall');
    for (final (i, pkg) in ['core', 'tool'].indexed) {
      j.effect(
        'upload-$pkg',
        1 + i,
        end: 3,
        place: copiesAt(20),
        key: 'upload#${i + 1}@r',
        after: null,
      );
      j.effect(
        'verify-$pkg',
        4 + i,
        end: 6,
        place: copiesAt(21),
        key: 'verify#1@$pkg',
        after: 'upload#${i + 1}@r',
      );
    }
    j.effect(
      'announce',
      9,
      end: 10,
      place: copiesAt(17),
      key: 'announce#1@r',
      after: null,
    );
    final session = j.data;
    expect(
      namesOf(
        copiesOf(
          copiesNode('viaCall'),
          places: placesOf('viaCall'),
          session: session,
        ),
        session,
      ),
      {
        1: ['upload-core', 'verify-core'],
        2: ['upload-tool', 'verify-tool'],
      },
    );
  });

  group('copies in copies', () {
    /// `nested` over core and tool, each built for arm and x64.
    Journal nestedJournal() {
      final j = Journal('7c3e-session', workflow: 'nested');
      var t = 1.0;
      for (final (i, pkg) in ['core', 'tool'].indexed) {
        j.effect(
          'fetch-$pkg',
          t++,
          end: t,
          place: copiesAt(27),
          key: 'fetch#${i + 1}@r',
          after: null,
        );
      }
      for (final (i, pkg) in ['core', 'tool'].indexed) {
        for (final (k, target) in ['arm', 'x64'].indexed) {
          j.effect(
            'build-$pkg-$target',
            t++,
            end: t,
            place: copiesAt(30),
            key: 'build#${k + 1}@$pkg',
            after: 'fetch#${i + 1}@r',
          );
          j.effect(
            'test-$pkg-$target',
            t++,
            end: t,
            place: copiesAt(31),
            key: 'test#1@$pkg$target',
            after: 'build#${k + 1}@$pkg',
          );
        }
        j.effect(
          'upload-$pkg',
          t++,
          end: t,
          place: copiesAt(34),
          key: 'upload#1@$pkg',
          after: 'fetch#${i + 1}@r',
        );
      }
      return j;
    }

    test('a copy of the outer frame holds its inner copies; the inner '
        'frame has a copy for each first effect whose predecessor is outside '
        'it', () {
      final session = nestedJournal().data;
      final places = placesOf('nested');
      final outer = copiesNode('nested');
      final copies = copiesOf(outer, places: places, session: session);
      expect(namesOf(copies, session), {
        1: [
          'fetch-core',
          'build-core-arm',
          'test-core-arm',
          'build-core-x64',
          'test-core-x64',
          'upload-core',
        ],
        2: [
          'fetch-tool',
          'build-tool-arm',
          'test-tool-arm',
          'build-tool-x64',
          'test-tool-x64',
          'upload-tool',
        ],
      });
      final inner = outer.body.node('2')! as CopiesNode;
      expect(
        namesOf(
          copiesOf(
            inner,
            places: places,
            session: session,
            effects: copies[1].effects,
          ),
          session,
        ),
        {
          1: ['build-tool-arm', 'test-tool-arm'],
          2: ['build-tool-x64', 'test-tool-x64'],
        },
        reason: 'the inner copies of copy 2, numbered in it',
      );
      expect(
        copiesOf(inner, places: places, session: session).length,
        4,
        reason: 'every inner copy of every outer one',
      );
    });
  });

  test('numbered by the time their first effect started, not by their '
      'records', () {
    final j = Journal('a1b2-session', workflow: 'inPlace')
      ..effect(
        'upload-late',
        5,
        place: copiesAt(7),
        key: 'upload#1@c',
        after: null,
      )
      ..effect(
        'upload-early',
        2,
        place: copiesAt(7),
        key: 'upload#2@c',
        after: null,
      );
    final copies = copiesOf(
      copiesNode('inPlace', '2'),
      places: placesOf('inPlace'),
      session: j.data,
    );
    expect(packagesOf(copies), {1: 'early', 2: 'late'});
  });

  test('a copy runs while an effect of it runs, failed once one failed; '
      'finished otherwise', () {
    final j = Journal('a1b2-session', workflow: 'inPlace');
    for (final (i, pkg) in ['core', 'tool', 'cli'].indexed) {
      j.effect(
        'upload-$pkg',
        1 + i,
        end: pkg == 'tool' ? null : 4,
        failed: pkg == 'cli',
        place: copiesAt(7),
        key: 'upload#${i + 1}@c',
        after: null,
      );
    }
    final copies = copiesOf(
      copiesNode('inPlace', '2'),
      places: placesOf('inPlace'),
      session: j.data,
    );
    expect(copies.map((copy) => copy.status), [
      CopyStatus.finished,
      CopyStatus.running,
      CopyStatus.failed,
    ]);
  });

  test('in a session whose process is gone, a copy that was running is '
      'interrupted; failed and finished ones stay (owner spec §6)', () {
    final j = Journal('a1b2-session', workflow: 'inPlace');
    for (final (i, pkg) in ['core', 'tool', 'cli'].indexed) {
      j.effect(
        'upload-$pkg',
        1 + i,
        end: pkg == 'tool' ? null : 4,
        failed: pkg == 'cli',
        place: copiesAt(7),
        key: 'upload#${i + 1}@c',
        after: null,
      );
    }
    j.processGone();
    final copies = copiesOf(
      copiesNode('inPlace', '2'),
      places: placesOf('inPlace'),
      session: j.data,
    );
    expect(copies.map((copy) => copy.status), [
      CopyStatus.finished,
      CopyStatus.interrupted,
      CopyStatus.failed,
    ]);
  });

  test('an effect rerun after another effect than before follows its record as '
      'it is now, whenever that effect started', () {
    final j = Journal('a1b2-session', workflow: 'inPlace')
      ..effect(
        'verify-core',
        3,
        end: 4,
        place: copiesAt(8),
        key: 'verify#1@core',
        // The rerun rewrote it: it follows tool's upload now.
        after: 'upload#2@c',
      )
      ..effect(
        'upload-core',
        1,
        end: 2,
        place: copiesAt(7),
        key: 'upload#1@c',
        after: null,
      )
      ..effect(
        'upload-tool',
        5,
        end: 6,
        place: copiesAt(7),
        key: 'upload#2@c',
        after: null,
      );
    final session = j.data;
    expect(
      namesOf(
        copiesOf(
          copiesNode('inPlace', '2'),
          places: placesOf('inPlace'),
          session: session,
        ),
        session,
      ),
      {
        1: ['upload-core'],
        2: ['verify-core', 'upload-tool'],
      },
    );
  });

  test('an effect whose predecessor has no record yet starts a copy', () {
    final j = Journal('a1b2-session', workflow: 'inPlace')
      ..effect(
        'verify-core',
        1,
        place: copiesAt(8),
        key: 'verify#1@core',
        after: 'upload#1@c',
      );
    final copies = copiesOf(
      copiesNode('inPlace', '2'),
      places: placesOf('inPlace'),
      session: j.data,
    );
    expect(copies.single.first.effectId, startsWith('a1b2-verify'));
  });

  test("the first effect's output hints at the copy", () {
    final session = inPlaceJournal().data;
    final copies = copiesOf(
      copiesNode('inPlace', '2'),
      places: placesOf('inPlace'),
      session: session,
    );
    expect(copies.map((copy) => copy.hintDocument), [
      'out-core',
      'out-tool',
      'out-cli',
    ]);
  });

  group('copyHint', () {
    test('a string as it is', () {
      expect(copyHint('core:uploaded'), 'core:uploaded');
    });

    test('anything else as JSON', () {
      expect(copyHint({'pkg': 'core'}), '{"pkg":"core"}');
      expect(copyHint(3), '3');
      expect(copyHint(null), 'null');
    });

    test('its start, cut with …', () {
      expect(copyHint('a' * 40), '${'a' * 23}…');
      expect(copyHint('one\ntwo'), 'one two');
    });
  });

  group('the frames the canvas goes down through', () {
    final inPlace = file.functions['lib/copies.dart#inPlace']!;
    final nested = file.functions['lib/copies.dart#nested']!;

    test('none above the workflow body: every effect is shown; the effects of '
        'the copies drawn there are named by their copy', () {
      final j = inPlaceJournal();
      final session = j.data;
      final shown = framesOf(
        bodyLevels(inPlace, file.functions, const []),
        places: placesOf('inPlace'),
        session: session,
      );
      expect(shown.frames, isEmpty);
      expect(shown.effects, session.state.effects);
      expect(shown.copy, isNull);
      // core, tool and cli started in that order.
      expect(shown.tagOf(j.effects[1].id), 'pkg 1');
      expect(shown.tagOf(j.effects[4].id), 'pkg 3', reason: "cli's verify");
      expect(shown.tagOf(j.effects.first.id), isNull, reason: 'plan');
      expect(shown.copyOf(j.effects[4].id), 'pkg 3');
    });

    test('a copy is named by the loop variable of its frame, or copy', () {
      expect(copyName(copiesNode('inPlace', '2'), 2), 'pkg 2');
      const unnamed = CopiesNode(
        id: '1',
        place: null,
        label: 'jobs.map(run)',
        body: GraphBody(nodes: [], edges: []),
      );
      expect(copyName(unnamed, 2), 'copy 2');
    });

    test('all copies of a frame: its header, done 2 of 3, every effect, each '
        'named by its copy', () {
      final j = inPlaceJournal();
      // cli's tag runs on.
      final tagCli = j.effects[5].id;
      j.events.removeWhere((e) => e is EffectFinished && e.effectId == tagCli);
      final session = j.data;
      final shown = framesOf(
        bodyLevels(inPlace, file.functions, const [Opened('2')]),
        places: placesOf('inPlace'),
        session: session,
      );
      final frame = shown.frames.single;
      expect(frame.depth, 1);
      expect(frame.title, 'each pkg in plan');
      expect(frame.countText, '×3 · in parallel');
      expect(frame.selected, isNull);
      expect(frame.choosable, isTrue);
      expect(frame.footer, 'done 2 of 3');
      expect(shown.effects, session.state.effects);
      expect(shown.copy, isNull);
      expect(shown.tagOf(tagCli), 'pkg 3');
      expect(shown.tagOf(j.effects.first.id), isNull);
    });

    test('one copy: its effects alone; pkg 2 · now verify', () {
      final j = Journal('a1b2-session', workflow: 'inPlace');
      for (final (i, pkg) in ['core', 'tool'].indexed) {
        j.effect(
          'upload',
          1 + i,
          end: 3,
          place: copiesAt(7),
          key: 'u$pkg',
          after: null,
        );
      }
      j.effect('verify', 4, place: copiesAt(8), key: 'v', after: 'utool');
      final session = j.data;
      final shown = framesOf(
        bodyLevels(inPlace, file.functions, const [Opened('2')]),
        places: placesOf('inPlace'),
        session: session,
        selected: {1: j.effects[1].id},
      );
      expect(shown.frames.single.selected!.number, 2);
      expect(shown.frames.single.footer, 'pkg 2 · now verify');
      expect(shown.effects.map((effect) => effect.effectId), [
        j.effects[1].id,
        j.effects[2].id,
      ]);
      expect(shown.copy, 'pkg 2');
      expect(
        shown.tagOf(j.effects[2].id),
        isNull,
        reason: 'the title names the copy chosen',
      );
      expect(shown.copyOf(j.effects[2].id), 'pkg 2');
      expect(shown.copyOf(j.effects[0].id), 'pkg 1');
    });

    test('one copy whose process is gone: pkg 2 · interrupted at verify '
        '(owner spec §6)', () {
      final j = Journal('a1b2-session', workflow: 'inPlace');
      for (final (i, pkg) in ['core', 'tool'].indexed) {
        j.effect(
          'upload',
          1 + i,
          end: 3,
          place: copiesAt(7),
          key: 'u$pkg',
          after: null,
        );
      }
      j
        ..effect('verify', 4, place: copiesAt(8), key: 'v', after: 'utool')
        ..processGone();
      final shown = framesOf(
        bodyLevels(inPlace, file.functions, const [Opened('2')]),
        places: placesOf('inPlace'),
        session: j.data,
        selected: {1: j.effects[1].id},
      );
      expect(shown.frames.single.footer, 'pkg 2 · interrupted at verify');
    });

    test('a copy done says so; one that failed, where', () {
      final j = Journal('a1b2-session', workflow: 'inPlace')
        ..effect(
          'upload',
          1,
          end: 2,
          place: copiesAt(7),
          key: 'u1',
          after: null,
        )
        ..effect(
          'upload',
          1,
          end: 2,
          place: copiesAt(7),
          key: 'u2',
          after: null,
        )
        ..effect(
          'verify',
          3,
          end: 4,
          failed: true,
          place: copiesAt(8),
          key: 'v2',
          after: 'u2',
        );
      final session = j.data;
      String footer(int copy) => framesOf(
        bodyLevels(inPlace, file.functions, const [Opened('2')]),
        places: placesOf('inPlace'),
        session: session,
        selected: {1: j.effects[copy].id},
      ).frames.single.footer;
      expect(footer(0), 'pkg 1 · done');
      expect(footer(1), 'pkg 2 · failed at verify');
      expect(
        framesOf(
          bodyLevels(inPlace, file.functions, const [Opened('2')]),
          places: placesOf('inPlace'),
          session: session,
        ).frames.single.footer,
        'done 1 of 2 · 1 failed',
      );
    });

    test('a copy that is gone, or a selection elsewhere, shows all', () {
      final session = inPlaceJournal().data;
      final shown = framesOf(
        bodyLevels(inPlace, file.functions, const [Opened('2')]),
        places: placesOf('inPlace'),
        session: session,
        selected: {1: 'nope', 2: session.state.effects[1].effectId},
      );
      expect(shown.frames.single.selected, isNull);
    });

    group('copies in copies', () {
      /// nested over core and tool, each built for arm and x64; the tests
      /// run.
      Journal nestedJournal() {
        final j = Journal('7c3e-session', workflow: 'nested');
        for (final (i, pkg) in ['core', 'tool'].indexed) {
          j.effect(
            'fetch',
            1 + i,
            end: 3,
            place: copiesAt(27),
            key: 'f$pkg',
            after: null,
          );
          for (final target in ['arm', 'x64']) {
            j.effect(
              'build',
              4 + i,
              end: 6,
              place: copiesAt(30),
              key: 'b$pkg$target',
              after: 'f$pkg',
            );
            j.effect(
              'test',
              7 + i,
              place: copiesAt(31),
              key: 't$pkg$target',
              after: 'b$pkg$target',
            );
          }
        }
        return j;
      }

      const path = [Opened('1'), Opened('2')];
      final levels = bodyLevels(nested, file.functions, path);
      ShownEffects shownOf(Journal j, [Map<int, String> selected = const {}]) =>
          framesOf(
            levels,
            places: placesOf('nested'),
            session: j.data,
            selected: selected,
          );

      test('inner copies are numbered within their outer copy, whether the '
          'outer frame shows one copy or all', () {
        final j = nestedJournal();
        final buildCoreX64 = j.effects[3].id;
        final buildToolX64 = j.effects[8].id;
        final all = shownOf(j);
        expect(all.frames.map((frame) => frame.copies.length), [2, 4]);
        expect(all.frames.last.copies.map((copy) => copy.number), [1, 2, 1, 2]);
        expect(all.copyOf(buildCoreX64), 'pkg 1 › target 2');
        expect(all.copyOf(buildToolX64), 'pkg 2 › target 2');
        expect(all.tagOf(buildToolX64), 'pkg 2 › target 2');
        final tool = shownOf(j, {1: j.effects[5].id});
        expect(tool.frames.map((frame) => frame.copies.length), [2, 2]);
        expect(tool.copyOf(buildToolX64), 'pkg 2 › target 2');
        expect(tool.tagOf(buildToolX64), 'target 2');
        expect(tool.copy, 'pkg 2');
        expect(tool.frames.last.footer, 'done 0 of 2');
      });

      test('while the outer frame shows all, no inner copy can be chosen: '
          'one of the outer is chosen first', () {
        final j = nestedJournal();
        final all = shownOf(j, {2: j.effects[8].id});
        final inner = all.frames.last;
        expect(inner.choosable, isFalse);
        expect(inner.chooseFirst, 'choose the outer pkg first');
        expect(inner.selected, isNull);
        expect(inner.footer, 'done 0 of 4');
        expect(all.frames.first.choosable, isTrue);
        expect(all.frames.first.chooseFirst, isNull);
      });

      test('both chosen: the path names both, the effects are the inner '
          "copy's", () {
        final j = nestedJournal();
        final session = j.data;
        final one = shownOf(j, {1: j.effects[5].id, 2: j.effects[8].id});
        expect(one.frames.last.selected!.number, 2);
        expect(one.copy, 'pkg 2 › target 2');
        expect(one.frames.last.footer, 'pkg 2 › target 2 · now test');
        expect(
          one.effects.map((effect) => session.effects[effect.effectId]!.name),
          ['build', 'test'],
        );
        expect(one.tagOf(j.effects[8].id), isNull);
      });

      test('the outer body drawn names the effects of the inner copies in it '
          'by both copies', () {
        final j = nestedJournal();
        final outer = framesOf(
          bodyLevels(nested, file.functions, const [Opened('1')]),
          places: placesOf('nested'),
          session: j.data,
        );
        expect(outer.tagOf(j.effects[0].id), 'pkg 1', reason: 'fetch');
        expect(outer.tagOf(j.effects[3].id), 'pkg 1 › target 2');
        expect(outer.levelCopies.single.copies, hasLength(4));
      });

      test('the workflow body drawn, the outer copies not opened, names the '
          'effects of the inner copies by both copies (decision 11)', () {
        final j = nestedJournal();
        final top = framesOf(
          bodyLevels(nested, file.functions, const []),
          places: placesOf('nested'),
          session: j.data,
        );
        expect(top.frames, isEmpty);
        expect(top.tagOf(j.effects[0].id), 'pkg 1', reason: 'fetch');
        expect(top.tagOf(j.effects[3].id), 'pkg 1 › target 2');
        expect(top.tagOf(j.effects[8].id), 'pkg 2 › target 2');
        expect(top.copyOf(j.effects[8].id), 'pkg 2 › target 2');
      });
    });

    test('the effects of copies in a function a call on the level drawn calls '
        'are named by their copy', () {
      final caller = GraphFunction(
        id: 'lib/copies.dart#release',
        name: 'release',
        place: 'lib/copies.dart:40',
        body: const GraphBody(
          nodes: [
            CallNode(
              id: '1',
              place: 'lib/copies.dart:41',
              functions: ['lib/copies.dart#inPlace'],
            ),
          ],
          edges: [],
        ),
      );
      final functions = {...file.functions, caller.id: caller};
      final j = inPlaceJournal();
      final shown = framesOf(
        bodyLevels(caller, functions, const []),
        places: EffectPlaces.of(caller, functions),
        session: j.data,
      );
      // core, tool and cli started in that order.
      expect(shown.tagOf(j.effects[1].id), 'pkg 1');
      expect(shown.tagOf(j.effects[3].id), 'pkg 3');
      expect(shown.tagOf(j.effects.first.id), isNull, reason: 'plan');
    });

    test('copies in a function two calls on the level drawn call are named '
        'once', () {
      // `await inPlace(f, staging); await inPlace(f, prod);`, or the two
      // branches of an if calling it.
      final caller = GraphFunction(
        id: 'lib/copies.dart#release',
        name: 'release',
        place: 'lib/copies.dart:40',
        body: const GraphBody(
          nodes: [
            CallNode(
              id: '1',
              place: 'lib/copies.dart:41',
              functions: ['lib/copies.dart#inPlace'],
            ),
            CallNode(
              id: '2',
              place: 'lib/copies.dart:42',
              functions: ['lib/copies.dart#inPlace'],
            ),
          ],
          edges: [],
        ),
      );
      final functions = {...file.functions, caller.id: caller};
      final j = inPlaceJournal();
      final shown = framesOf(
        bodyLevels(caller, functions, const []),
        places: EffectPlaces.of(caller, functions),
        session: j.data,
      );
      expect(shown.tagOf(j.effects[1].id), 'pkg 1');
      expect(shown.copyOf(j.effects[3].id), 'pkg 3');
      expect(shown.levelCopies, hasLength(1));
    });

    test('copies in a function called both on the level drawn and inside '
        'copies are named once, within the copy around them (decision '
        '11)', () {
      final deploy = GraphFunction(
        id: 'lib/d.dart#deploy',
        name: 'deploy',
        place: 'lib/d.dart:1',
        body: const GraphBody(
          nodes: [
            CopiesNode(
              id: '1',
              place: 'lib/d.dart:2',
              label: 's in servers',
              body: GraphBody(
                nodes: [EffectNode(id: '1', place: 'lib/d.dart:3', name: 'up')],
                edges: [],
              ),
            ),
          ],
          edges: [],
        ),
      );
      // `await deploy(f); await Future.wait([for (r in regions) () async {
      // await f.effect('prepare', …); await deploy(f); }()]);`
      final release = GraphFunction(
        id: 'lib/d.dart#release',
        name: 'release',
        place: 'lib/d.dart:6',
        body: const GraphBody(
          nodes: [
            CallNode(
              id: '1',
              place: 'lib/d.dart:7',
              functions: ['lib/d.dart#deploy'],
            ),
            CopiesNode(
              id: '2',
              place: 'lib/d.dart:8',
              label: 'r in regions',
              body: GraphBody(
                nodes: [
                  EffectNode(id: '1', place: 'lib/d.dart:9', name: 'prepare'),
                  CallNode(
                    id: '2',
                    place: 'lib/d.dart:10',
                    functions: ['lib/d.dart#deploy'],
                  ),
                ],
                edges: [],
              ),
            ),
          ],
          edges: [],
        ),
      );
      final functions = {deploy.id: deploy, release.id: release};
      final j = Journal('d1e2-session', workflow: 'release');
      for (final (i, server) in ['a', 'b'].indexed) {
        j.effect(
          'up',
          1 + i,
          end: 3,
          place: 'lib/d.dart:3',
          key: 'u$server',
          after: null,
        );
      }
      for (final (i, region) in ['eu', 'us'].indexed) {
        j.effect(
          'prepare',
          4 + i * 3,
          end: 5 + i * 3,
          place: 'lib/d.dart:9',
          key: 'p$region',
          after: null,
        );
        for (final (k, server) in ['a', 'b'].indexed) {
          j.effect(
            'up',
            5 + i * 3 + k / 10,
            end: 6 + i * 3,
            place: 'lib/d.dart:3',
            key: 'u$region$server',
            after: 'p$region',
          );
        }
      }
      final shown = framesOf(
        bodyLevels(release, functions, const []),
        places: EffectPlaces.of(release, functions),
        session: j.data,
      );
      String? tagOf(String key) =>
          shown.tagOf(j.effects.singleWhere((s) => s.key == key).id);

      // The servers of a region are numbered within it.
      expect(tagOf('peu'), 'r 3');
      expect(tagOf('ueua'), 'r 3 › s 1');
      expect(tagOf('uusb'), 'r 4 › s 2');
      // By its place an effect of the call outside regions is in the regions
      // frame too: each such effect is a copy of it of its own (spec §9).
      expect(tagOf('ua'), 'r 1 › s 1');
      expect(tagOf('ub'), 'r 2 › s 1');
      expect(shown.levelCopies, hasLength(2));
    });

    test('copies in a workflow that calls itself from inside them keep '
        'their names', () {
      // A parallel crawler: `crawl(f, url)` fetches the page, then
      // `Future.wait([for (l in links) () async { await f.effect('visit', …);
      // await crawl(f, l); }()])`.
      final crawl = GraphFunction(
        id: 'lib/c.dart#crawl',
        name: 'crawl',
        place: 'lib/c.dart:1',
        body: const GraphBody(
          nodes: [
            EffectNode(id: '1', place: 'lib/c.dart:2', name: 'fetch'),
            CopiesNode(
              id: '2',
              place: 'lib/c.dart:3',
              label: 'l in links',
              body: GraphBody(
                nodes: [
                  EffectNode(id: '1', place: 'lib/c.dart:4', name: 'visit'),
                  CallNode(
                    id: '2',
                    place: 'lib/c.dart:5',
                    functions: ['lib/c.dart#crawl'],
                  ),
                ],
                edges: [],
              ),
            ),
          ],
          edges: [],
        ),
      );
      final functions = {crawl.id: crawl};
      final j = Journal('c4d5-session', workflow: 'crawl')
        ..effect(
          'fetch',
          1,
          end: 2,
          place: 'lib/c.dart:2',
          key: 'f',
          after: null,
        )
        ..effect(
          'visit',
          3,
          end: 4,
          place: 'lib/c.dart:4',
          key: 'a',
          after: null,
        )
        ..effect(
          'visit',
          5,
          end: 6,
          place: 'lib/c.dart:4',
          key: 'b',
          after: null,
        );
      final shown = framesOf(
        bodyLevels(crawl, functions, const []),
        places: EffectPlaces.of(crawl, functions),
        session: j.data,
      );

      // By place the fetch of a crawl called in a copy is in the copies too
      // (spec §9): the fetch here, which follows nothing, is a copy of its
      // own.
      expect(
        [for (final effect in j.effects) shown.tagOf(effect.id)],
        ['l 1', 'l 2', 'l 3'],
      );
      expect(shown.levelCopies.single.copies, hasLength(3));
    });
  });

  group('over sessions the real library wrote (recordedCopies)', () {
    final recorded = recordedCopies();
    final functions = recorded.graph.functions;
    GraphFunction function(String name) => functions['lib/copies.dart#$name']!;
    EffectPlaces placesOfRecorded(String name) =>
        EffectPlaces.of(function(name), functions);
    CopiesNode frameOf(GraphBody body) =>
        body.nodes.whereType<CopiesNode>().single;

    /// What each effect of [copy] of [session] gave.
    List<String> outputsOf(Copy copy) => [
      for (final effect in copy.effects)
        '${recorded.documents[effect.outputId]}',
    ];

    for (final workflow in ['inPlace', 'viaMap', 'viaCall']) {
      test('$workflow: a copy for each package, its effects all its own, '
          'whatever order they ran in', () {
        final session = recorded.sessions[workflow]!;
        final copies = copiesOf(
          frameOf(function(workflow).body),
          places: placesOfRecorded(workflow),
          session: session,
        );
        expect(copies, hasLength(3));
        final packages = <String>{};
        for (final copy in copies) {
          final package = outputsOf(copy).first.split(':').first;
          packages.add(package);
          expect(
            [
              for (final effect in copy.effects)
                session.effects[effect.effectId]!.name,
            ],
            ['upload', 'verify', 'tag'],
          );
          expect(outputsOf(copy), everyElement(startsWith('$package:')));
        }
        expect(packages, {'core', 'tool', 'cli'});
        // plan and announce are in none.
        final inCopies = {
          for (final copy in copies)
            for (final effect in copy.effects) effect.effectId,
        };
        expect(
          [
            for (final effect in session.state.effects)
              if (!inCopies.contains(effect.effectId))
                session.effects[effect.effectId]!.name,
          ],
          [if (workflow == 'inPlace') 'plan', 'announce'],
        );
      });
    }

    test('nested: a copy for each package, an inner copy for each target '
        'within it, numbered within its package', () {
      final session = recorded.sessions['nested']!;
      final places = placesOfRecorded('nested');
      final outer = frameOf(function('nested').body);
      final inner = frameOf(outer.body);
      final copies = copiesOf(outer, places: places, session: session);
      expect(copies, hasLength(2));
      for (final copy in copies) {
        final package = outputsOf(copy).first.split(':').first;
        expect(outputsOf(copy), everyElement(startsWith('$package:')));
        final targets = copiesOf(
          inner,
          places: places,
          session: session,
          effects: copy.effects,
        );
        expect(targets.map((target) => target.number), [1, 2]);
        for (final target in targets) {
          final first = outputsOf(target).first;
          final name = first.substring(first.indexOf('/') + 1).split(':')[0];
          expect(outputsOf(target), everyElement(contains('/$name:')));
        }
      }
      // The same names whether the outer frame shows one copy or all.
      final levels = bodyLevels(function('nested'), functions, [
        Opened(outer.id),
        Opened(inner.id),
      ]);
      final all = framesOf(levels, places: places, session: session);
      for (final copy in copies) {
        final one = framesOf(
          levels,
          places: places,
          session: session,
          selected: {1: copy.id},
        );
        for (final effect in copy.effects) {
          expect(
            one.copyOf(effect.effectId),
            all.copyOf(effect.effectId),
            reason: session.effects[effect.effectId]!.name,
          );
        }
      }
    });
  });
}
