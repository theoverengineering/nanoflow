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

    test('none above the workflow body: every step is shown; the steps of '
        'the copies drawn there are named by their copy', () {
      final j = inPlaceJournal();
      final session = j.data;
      final shown = framesOf(
        bodyLevels(inPlace, file.functions, const []),
        places: placesOf('inPlace'),
        session: session,
      );
      expect(shown.frames, isEmpty);
      expect(shown.steps, session.state.steps);
      expect(shown.copy, isNull);
      // core, tool and cli started in that order.
      expect(shown.tagOf(j.steps[1].id), 'pkg 1');
      expect(shown.tagOf(j.steps[4].id), 'pkg 3', reason: "cli's verify");
      expect(shown.tagOf(j.steps.first.id), isNull, reason: 'plan');
      expect(shown.copyOf(j.steps[4].id), 'pkg 3');
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

    test('all copies of a frame: its header, done 2 of 3, every step, each '
        'named by its copy', () {
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
      expect(frame.choosable, isTrue);
      expect(frame.footer, 'done 2 of 3');
      expect(shown.steps, session.state.steps);
      expect(shown.copy, isNull);
      expect(shown.tagOf(tagCli), 'pkg 3');
      expect(shown.tagOf(j.steps.first.id), isNull);
    });

    test('one copy: its steps alone; pkg 2 · now verify', () {
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
      expect(shown.frames.single.footer, 'pkg 2 · now verify');
      expect(shown.steps.map((step) => step.stepId), [
        j.steps[1].id,
        j.steps[2].id,
      ]);
      expect(shown.copy, 'pkg 2');
      expect(
        shown.tagOf(j.steps[2].id),
        isNull,
        reason: 'the title names the copy chosen',
      );
      expect(shown.copyOf(j.steps[2].id), 'pkg 2');
      expect(shown.copyOf(j.steps[0].id), 'pkg 1');
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
        selected: {1: 'nope', 2: session.state.steps[1].stepId},
      );
      expect(shown.frames.single.selected, isNull);
    });

    group('copies in copies', () {
      /// nested over core and tool, each built for arm and x64; the tests
      /// run.
      Journal nestedJournal() {
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
        return j;
      }

      const path = [Opened('1'), Opened('2')];
      final levels = bodyLevels(nested, file.functions, path);
      ShownSteps shownOf(Journal j, [Map<int, String> selected = const {}]) =>
          framesOf(
            levels,
            places: placesOf('nested'),
            session: j.data,
            selected: selected,
          );

      test('inner copies are numbered within their outer copy, whether the '
          'outer frame shows one copy or all', () {
        final j = nestedJournal();
        final buildCoreX64 = j.steps[3].id;
        final buildToolX64 = j.steps[8].id;
        final all = shownOf(j);
        expect(all.frames.map((frame) => frame.copies.length), [2, 4]);
        expect(all.frames.last.copies.map((copy) => copy.number), [1, 2, 1, 2]);
        expect(all.copyOf(buildCoreX64), 'pkg 1 › target 2');
        expect(all.copyOf(buildToolX64), 'pkg 2 › target 2');
        expect(all.tagOf(buildToolX64), 'pkg 2 › target 2');
        final tool = shownOf(j, {1: j.steps[5].id});
        expect(tool.frames.map((frame) => frame.copies.length), [2, 2]);
        expect(tool.copyOf(buildToolX64), 'pkg 2 › target 2');
        expect(tool.tagOf(buildToolX64), 'target 2');
        expect(tool.copy, 'pkg 2');
        expect(tool.frames.last.footer, 'done 0 of 2');
      });

      test('while the outer frame shows all, no inner copy can be chosen: '
          'one of the outer is chosen first', () {
        final j = nestedJournal();
        final all = shownOf(j, {2: j.steps[8].id});
        final inner = all.frames.last;
        expect(inner.choosable, isFalse);
        expect(inner.chooseFirst, 'choose a pkg one level up');
        expect(inner.selected, isNull);
        expect(inner.footer, 'done 0 of 4');
        expect(all.frames.first.choosable, isTrue);
        expect(all.frames.first.chooseFirst, isNull);
      });

      test('both chosen: the path names both, the steps are the inner '
          "copy's", () {
        final j = nestedJournal();
        final session = j.data;
        final one = shownOf(j, {1: j.steps[5].id, 2: j.steps[8].id});
        expect(one.frames.last.selected!.number, 2);
        expect(one.copy, 'pkg 2 › target 2');
        expect(one.frames.last.footer, 'pkg 2 › target 2 · now test');
        expect(one.steps.map((step) => session.steps[step.stepId]!.name), [
          'build',
          'test',
        ]);
        expect(one.tagOf(j.steps[8].id), isNull);
      });

      test('the outer body drawn names the steps of the inner copies in it '
          'by both copies', () {
        final j = nestedJournal();
        final outer = framesOf(
          bodyLevels(nested, file.functions, const [Opened('1')]),
          places: placesOf('nested'),
          session: j.data,
        );
        expect(outer.tagOf(j.steps[0].id), 'pkg 1', reason: 'fetch');
        expect(outer.tagOf(j.steps[3].id), 'pkg 1 › target 2');
        expect(outer.levelCopies.single.copies, hasLength(4));
      });
    });
  });

  group('over sessions the real library wrote (recordedCopies)', () {
    final recorded = recordedCopies();
    final functions = recorded.graph.functions;
    GraphFunction function(String name) => functions['lib/copies.dart#$name']!;
    StepPlaces placesOfRecorded(String name) =>
        StepPlaces.of(function(name), functions);
    CopiesNode frameOf(GraphBody body) =>
        body.nodes.whereType<CopiesNode>().single;

    /// What each step of [copy] of [session] gave.
    List<String> outputsOf(Copy copy) => [
      for (final step in copy.steps) '${recorded.documents[step.outputId]}',
    ];

    for (final workflow in ['inPlace', 'viaMap', 'viaCall']) {
      test('$workflow: a copy for each package, its steps all its own, '
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
            [for (final step in copy.steps) session.steps[step.stepId]!.name],
            ['upload', 'verify', 'tag'],
          );
          expect(outputsOf(copy), everyElement(startsWith('$package:')));
        }
        expect(packages, {'core', 'tool', 'cli'});
        // plan and announce are in none.
        final inCopies = {
          for (final copy in copies)
            for (final step in copy.steps) step.stepId,
        };
        expect(
          [
            for (final step in session.state.steps)
              if (!inCopies.contains(step.stepId))
                session.steps[step.stepId]!.name,
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
          steps: copy.steps,
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
        for (final step in copy.steps) {
          expect(
            one.copyOf(step.stepId),
            all.copyOf(step.stepId),
            reason: session.steps[step.stepId]!.name,
          );
        }
      }
    });
  });
}
