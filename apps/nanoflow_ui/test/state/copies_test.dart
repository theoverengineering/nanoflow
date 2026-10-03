import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/body_path.dart';
import 'package:nanoflow_ui/state/copies.dart';
import 'package:nanoflow_ui/state/session_feed.dart';
import 'package:nanoflow_ui/state/step_places.dart';

import 'support.dart';

// The sessions are those the workflows of `copiesGraphJson` write: the keys
// and `after`s are as the library gives them (decision D1), shortened. A
// copy's steps follow one another in it; its first step follows the step
// before the copies, or none.

final file = copiesGraphFile();

StepPlaces placesOf(String workflow) =>
    StepPlaces.of(file.functions['lib/copies.dart#$workflow'], file.functions);

CopiesNode copiesNode(String workflow, [String id = '1']) =>
    file.functions['lib/copies.dart#$workflow']!.body.node(id)! as CopiesNode;

/// The names of each copy's steps, by copy number.
Map<int, List<String>> namesOf(List<Copy> copies, SessionData session) => {
  for (final copy in copies)
    copy.number: [
      for (final step in copy.steps) session.steps[step.stepId]!.name,
    ],
};

/// The package of each copy, by number: the name of its first step ends
/// with it (`upload-core`).
Map<int, String> packagesOf(List<Copy> copies) => {
  for (final copy in copies) copy.number: copy.first.stepId.split('-')[2],
};

/// `inPlace` over core, tool and cli: the copies start in that order, and
/// cli's upload ends first.
Journal inPlaceJournal() {
  final j = Journal('a1b2-session', workflow: 'inPlace');
  j.step('plan', 1, end: 2, place: copiesAt(4), key: 'plan#1@r', after: null);
  for (final (i, pkg) in ['core', 'tool', 'cli'].indexed) {
    j.step(
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
    j.step(
      'verify-$pkg',
      7 + i,
      end: 10 + i,
      place: copiesAt(8),
      key: 'verify#1@$pkg',
      after: 'upload#${3 - i}@c',
    );
    j.step(
      'tag-$pkg',
      10 + i,
      end: 13 + i,
      place: copiesAt(9),
      key: 'tag#1@$pkg',
      after: 'verify#1@$pkg',
    );
  }
  j.step(
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
  test('in place: a copy is a chain of steps in the frame by after; plan and '
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

  test('given to map: the first steps follow no step', () {
    final j = Journal('c3d4-session', workflow: 'inPlace');
    for (final (i, pkg) in ['core', 'tool'].indexed) {
      j.step(
        'upload-$pkg',
        1 + i,
        end: 3,
        place: copiesAt(7),
        key: 'upload#${i + 1}@r',
        after: null,
      );
    }
    for (final (i, pkg) in ['tool', 'core'].indexed) {
      j.step(
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

  test('through a call: the steps of the function called in the frame are '
      'in it', () {
    final j = Journal('e5f6-session', workflow: 'viaCall');
    for (final (i, pkg) in ['core', 'tool'].indexed) {
      j.step(
        'upload-$pkg',
        1 + i,
        end: 3,
        place: copiesAt(20),
        key: 'upload#${i + 1}@r',
        after: null,
      );
      j.step(
        'verify-$pkg',
        4 + i,
        end: 6,
        place: copiesAt(21),
        key: 'verify#1@$pkg',
        after: 'upload#${i + 1}@r',
      );
    }
    j.step(
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
        j.step(
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
          j.step(
            'build-$pkg-$target',
            t++,
            end: t,
            place: copiesAt(30),
            key: 'build#${k + 1}@$pkg',
            after: 'fetch#${i + 1}@r',
          );
          j.step(
            'test-$pkg-$target',
            t++,
            end: t,
            place: copiesAt(31),
            key: 'test#1@$pkg$target',
            after: 'build#${k + 1}@$pkg',
          );
        }
        j.step(
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
        'frame has a copy for each first step whose predecessor is outside '
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
            steps: copies[1].steps,
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

  test('numbered by the time their first step started, not by their '
      'records', () {
    final j = Journal('a1b2-session', workflow: 'inPlace')
      ..step(
        'upload-late',
        5,
        place: copiesAt(7),
        key: 'upload#1@c',
        after: null,
      )
      ..step(
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

  test('a copy runs while a step of it runs, failed once one failed; '
      'finished otherwise', () {
    final j = Journal('a1b2-session', workflow: 'inPlace');
    for (final (i, pkg) in ['core', 'tool', 'cli'].indexed) {
      j.step(
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

  test('a step rerun after another step than before follows its record as '
      'it is now, whenever that step started', () {
    final j = Journal('a1b2-session', workflow: 'inPlace')
      ..step(
        'verify-core',
        3,
        end: 4,
        place: copiesAt(8),
        key: 'verify#1@core',
        // The rerun rewrote it: it follows tool's upload now.
        after: 'upload#2@c',
      )
      ..step(
        'upload-core',
        1,
        end: 2,
        place: copiesAt(7),
        key: 'upload#1@c',
        after: null,
      )
      ..step(
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

  test('a step whose predecessor has no record yet starts a copy', () {
    final j = Journal('a1b2-session', workflow: 'inPlace')
      ..step(
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
    expect(copies.single.first.stepId, startsWith('a1b2-verify'));
  });

  test("the first step's output hints at the copy", () {
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

    test('none above the workflow body: every step is shown', () {
      final session = inPlaceJournal().data;
      final shown = framesOf(
        bodyLevels(inPlace, file.functions, const []),
        places: placesOf('inPlace'),
        session: session,
      );
      expect(shown.frames, isEmpty);
      expect(shown.steps, session.state.steps);
      expect(shown.copy, isNull);
    });

    test('all copies of a frame: its header, done 2 of 3, every step', () {
      final j = inPlaceJournal();
      // cli's tag runs on.
      final tagCli = j.steps[5].id;
      j.events.removeWhere((e) => e is StepFinished && e.stepId == tagCli);
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
      expect(frame.footer, 'done 2 of 3');
      expect(shown.steps, session.state.steps);
      expect(shown.copy, isNull);
      expect(shown.copyNumbers[tagCli], 3);
      expect(shown.copyNumbers[j.steps.first.id], isNull);
    });

    test('one copy: its steps alone; copy 2 · now verify', () {
      final j = Journal('a1b2-session', workflow: 'inPlace');
      for (final (i, pkg) in ['core', 'tool'].indexed) {
        j.step(
          'upload',
          1 + i,
          end: 3,
          place: copiesAt(7),
          key: 'u$pkg',
          after: null,
        );
      }
      j.step('verify', 4, place: copiesAt(8), key: 'v', after: 'utool');
      final session = j.data;
      final shown = framesOf(
        bodyLevels(inPlace, file.functions, const [Opened('2')]),
        places: placesOf('inPlace'),
        session: session,
        selected: {1: j.steps[1].id},
      );
      expect(shown.frames.single.selected!.number, 2);
      expect(shown.frames.single.footer, 'copy 2 · now verify');
      expect(shown.steps.map((step) => step.stepId), [
        j.steps[1].id,
        j.steps[2].id,
      ]);
      expect(shown.copy, 'copy 2');
      expect(shown.copyNumbers, isEmpty);
      expect(shown.copyOf(j.steps[2].id), 'copy 2');
      expect(shown.copyOf(j.steps[0].id), 'copy 1');
    });

    test('a copy done says so; one that failed, where', () {
      final j = Journal('a1b2-session', workflow: 'inPlace')
        ..step('upload', 1, end: 2, place: copiesAt(7), key: 'u1', after: null)
        ..step('upload', 1, end: 2, place: copiesAt(7), key: 'u2', after: null)
        ..step(
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
        selected: {1: j.steps[copy].id},
      ).frames.single.footer;
      expect(footer(0), 'copy 1 · done');
      expect(footer(1), 'copy 2 · failed at verify');
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
        selected: {1: 'nope', 2: session.state.steps[1].stepId},
      );
      expect(shown.frames.single.selected, isNull);
    });

    test('copies in copies: the inner frame has the copies of the outer '
        'one selected; the path names both', () {
      final j = Journal('7c3e-session', workflow: 'nested');
      for (final (i, pkg) in ['core', 'tool'].indexed) {
        j.step(
          'fetch',
          1 + i,
          end: 3,
          place: copiesAt(27),
          key: 'f$pkg',
          after: null,
        );
        for (final target in ['arm', 'x64']) {
          j.step(
            'build',
            4 + i,
            end: 6,
            place: copiesAt(30),
            key: 'b$pkg$target',
            after: 'f$pkg',
          );
          j.step(
            'test',
            7 + i,
            place: copiesAt(31),
            key: 't$pkg$target',
            after: 'b$pkg$target',
          );
        }
      }
      final session = j.data;
      const path = [Opened('1'), Opened('2')];
      final levels = bodyLevels(nested, file.functions, path);
      final all = framesOf(
        levels,
        places: placesOf('nested'),
        session: session,
      );
      expect(all.frames.map((frame) => frame.copies.length), [2, 4]);
      final fetchTool = j.steps[5].id;
      final buildToolX64 = j.steps[8].id;
      final one = framesOf(
        levels,
        places: placesOf('nested'),
        session: session,
        selected: {1: fetchTool, 2: buildToolX64},
      );
      expect(one.frames.map((frame) => frame.copies.length), [2, 2]);
      expect(one.frames.last.selected!.number, 2);
      expect(one.copy, 'copy 2 › copy 2');
      expect(one.frames.last.footer, 'copy 2 › copy 2 · now test');
      expect(one.steps.map((step) => session.steps[step.stepId]!.name), [
        'build',
        'test',
      ]);
      final outer = framesOf(
        levels,
        places: placesOf('nested'),
        session: session,
        selected: {1: fetchTool},
      );
      expect(outer.copy, 'copy 2');
      expect(outer.frames.last.footer, 'done 0 of 2');
      expect(outer.copyNumbers[buildToolX64], 2);
      expect(outer.copyOf(buildToolX64), 'copy 2 › copy 2');
    });
  });
}
