import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/body_path.dart';
import 'package:nanoflow_ui/state/in_place.dart';
import 'package:test/test.dart';

import '../layout/support.dart';

void main() {
  final release = loadGraphFile('release');
  final releaseFunction = functionOf(release, 'release');
  final inline = loadGraphFile('inline');
  final viaCall = functionOf(inline, 'viaCall');
  const publish = Opened('5', functionId: 'lib/publish.dart#publish');

  List<InPlaceFrame> framesAt(
    GraphFunction workflow,
    Map<String, GraphFunction> functions,
    List<Opened> path,
    Expansions expansions,
  ) => inPlaceFrames(
    bodyLevels(workflow, functions, path),
    functions,
    expansions,
  );

  group('Expansions', () {
    test('follow keeps each node found again, in the body found, and forgets '
        'the rest', () {
      const upload = Opened('1');
      const gone = Opened('9', functionId: 'lib/x.dart#x');
      final expansions = Expansions()
        ..expand(const [], publish)
        ..expand(const [publish], upload)
        ..expand(const [], gone);
      expansions.follow(
        (path) => switch (path) {
          [Opened(nodeId: '5')] => const [
            Opened('6', functionId: 'lib/publish.dart#publish'),
          ],
          [Opened(nodeId: '5'), Opened(nodeId: '1')] => const [
            Opened('6', functionId: 'lib/publish.dart#publish'),
            Opened('2'),
          ],
          _ => null,
        },
      );
      const moved = Opened('6', functionId: 'lib/publish.dart#publish');
      expect(expansions.at(const []), [moved]);
      expect(expansions.at(const [moved]), [const Opened('2')]);
      expect(expansions.at(const [publish]), isEmpty);
    });

    test('a node is expanded in the body at one path, and collapsed there', () {
      final expansions = Expansions()..expand(const [], publish);
      expect(expansions.at(const []), [publish]);
      expect(expansions.at(const [publish]), isEmpty);

      expansions.collapse(const [], '5');
      expect(expansions.at(const []), isEmpty);
    });

    test('a node expanded again to another function shows that one; in '
        'another body, the same id is another node', () {
      const other = Opened('5', functionId: 'lib/publish.dart#other');
      final expansions = Expansions()
        ..expand(const [], publish)
        ..expand(const [], other)
        ..expand(const [publish], const Opened('5'));
      expect(expansions.at(const []), [other]);
      expect(expansions.at(const [publish]), [const Opened('5')]);
      expect(expansions.at(const [other]), isEmpty);
    });

    test('collapsing a frame forgets what was expanded in it; clear forgets '
        'everything', () {
      final expansions = Expansions()
        ..expand(const [], const Opened('1'))
        ..expand(const [Opened('1')], const Opened('1', functionId: 'f'))
        ..expand(const [Opened('2')], const Opened('3'));
      expansions.collapse(const [], '1');
      expect(expansions.at(const [Opened('1')]), isEmpty);
      expect(expansions.at(const [Opened('2')]), [const Opened('3')]);

      expansions.clear();
      expect(expansions.isEmpty, isTrue);
      expect(expansions.at(const [Opened('2')]), isEmpty);
    });
  });

  group('inPlaceFrames', () {
    test('a call expanded in the body drawn is a frame of its function\'s '
        'body, titled as its crumb would be', () {
      final frames = framesAt(
        releaseFunction,
        release.functions,
        const [],
        Expansions()..expand(const [], publish),
      );
      final frame = frames.single;
      expect(frame.nodeId, '5');
      expect(frame.node, releaseFunction.body.node('5'));
      expect(frame.path, const [publish]);
      expect(frame.level.title, 'publish()');
      expect(
        frame.level.body,
        release.functions['lib/publish.dart#publish']!.body,
      );
      expect(
        [for (final level in frame.levels) level.title],
        ['release', 'publish()'],
      );
      expect(frame.frames, isEmpty);
    });

    test('a frame in a frame: copies, and the call in their body', () {
      const copies = Opened('1');
      const call = Opened('1', functionId: 'lib/inline.dart#publish');
      final frames = framesAt(
        viaCall,
        inline.functions,
        const [],
        Expansions()
          ..expand(const [], copies)
          ..expand(const [copies], call),
      );
      expect(frames.single.level.title, 'pkg in packages');
      final inner = frames.single.frames.single;
      expect(inner.path, const [copies, call]);
      expect(inner.level.title, 'publish()');
      expect(
        [for (final level in inner.levels) level.title],
        ['viaCall', 'pkg in packages', 'publish()'],
      );
    });

    test('frames of the level drawn only: those of the levels above or '
        'below are not drawn', () {
      const copies = Opened('1');
      final expansions = Expansions()
        ..expand(const [], copies)
        ..expand(const [copies], const Opened('1', functionId: 'x'));
      // Drilled into the copies: only what is expanded in their body.
      final frames = framesAt(viaCall, inline.functions, const [
        copies,
      ], Expansions()..expand(const [copies], const Opened('9')));
      expect(frames, isEmpty);
      expect(
        framesAt(viaCall, inline.functions, const [copies], expansions),
        isEmpty,
        reason: 'the call does not go to x',
      );
    });

    test('nodes the body does not have, effects, and functions a call does '
        'not go to are not drawn in place', () {
      final frames = framesAt(
        releaseFunction,
        release.functions,
        const [],
        Expansions()
          ..expand(const [], const Opened('9'))
          ..expand(const [], const Opened('1'))
          ..expand(const [], const Opened('5', functionId: 'lib/x.dart#x')),
      );
      expect(frames, isEmpty);
    });
  });

  test('a path\'s key tells nodes and functions apart', () {
    expect(levelKey(const [Opened('1')]), isNot(levelKey(const [Opened('2')])));
    expect(
      levelKey(const [Opened('1', functionId: 'a')]),
      isNot(levelKey(const [Opened('1', functionId: 'b')])),
    );
    expect(
      levelKey(const [Opened('1'), Opened('2')]),
      isNot(levelKey(const [Opened('1')])),
    );
  });
}
