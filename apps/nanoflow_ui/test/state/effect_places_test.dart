import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/effect_places.dart';

import 'support.dart';

void main() {
  final file = packagesGraphFile();
  EffectPlaces effectPlacesOf(String workflow) => EffectPlaces.of(
    file.functions['lib/packages.dart#$workflow'],
    file.functions,
  );
  GraphNode nodeOf(GraphBody body, String id) => body.node(id)!;

  /// The places of [nodes].
  Set<String?> placesOf(Set<EffectNode> nodes) => {
    for (final node in nodes) node.place,
  };

  /// An effect [name] that ran at [place].
  Effect effectAt(String? place, [String name = 'upload']) => Effect(
    id: 'effect-$name',
    sessionId: 'session',
    name: name,
    key: '$name#1@0000000000000000',
    after: null,
    place: place,
    outputId: null,
    log: logFileName,
  );

  group('isPlaceOf', () {
    test('an effect is at the place of a node it equals', () {
      expect(isPlaceOf('lib/packages.dart:7', 'lib/packages.dart:7'), isTrue);
    });

    test('an effect is at the place of a node it ends with after a /', () {
      expect(
        isPlaceOf(
          '/Users/me/packages/lib/packages.dart:7',
          'lib/packages.dart:7',
        ),
        isTrue,
      );
    });

    test('not at another line, nor at a path that only ends the same', () {
      expect(isPlaceOf('lib/packages.dart:70', 'lib/packages.dart:7'), isFalse);
      expect(isPlaceOf('lib/packages.dart:7', 'lib/packages.dart:70'), isFalse);
      expect(
        isPlaceOf('mylib/packages.dart:7', 'lib/packages.dart:7'),
        isFalse,
      );
    });
  });

  group('EffectPlaces', () {
    test('has every effect node the workflow reaches: its body, the '
        'functions it calls and those they call', () {
      expect(placesOf(effectPlacesOf('inPlace').nodes), {
        for (final line in [4, 7, 8, 9, 12]) packagesAt(line),
      });
      expect(placesOf(effectPlacesOf('viaCall').nodes), {
        for (final line in [17, 20, 21, 22]) packagesAt(line),
      });
      expect(placesOf(effectPlacesOf('nested').nodes), {
        for (final line in [27, 30, 31, 34, 37]) packagesAt(line),
      });
    });

    test('no nodes without a workflow', () {
      expect(EffectPlaces.of(null, file.functions).nodes, isEmpty);
    });

    test('an effect is at the nodes of its place (D13)', () {
      final places = effectPlacesOf('inPlace');
      expect(placesOf(places.of(effectAt(packagesAt(7)))), {packagesAt(7)});
      expect(
        placesOf(places.of(effectAt('/home/me/packages/${packagesAt(7)}'))),
        {packagesAt(7)},
      );
      expect(
        places.of(effectAt(packagesAt(20))),
        isEmpty,
        reason: 'publish is not called',
      );
      expect(places.of(effectAt(null)), isEmpty);
      expect(places.of(null), isEmpty);
    });

    // `dart format` keeps short parallel effects on one line.
    final oneLine = GraphFunction(
      id: 'lib/ci.dart#check',
      name: 'check',
      place: 'lib/ci.dart:1',
      body: const GraphBody(
        nodes: [
          EffectNode(id: '1', place: 'lib/ci.dart:2', name: 'lint'),
          EffectNode(id: '2', place: 'lib/ci.dart:2', name: 'test'),
          EffectNode(id: '3', place: 'lib/ci.dart:3', name: "'deploy-' + env"),
          EffectNode(id: '4', place: 'lib/ci.dart:3', name: "'notify-' + env"),
        ],
        edges: [],
      ),
    );
    final ci = EffectPlaces.of(oneLine, {oneLine.id: oneLine});

    test('of the nodes at its place, an effect is at those of its name', () {
      expect(ci.of(effectAt('lib/ci.dart:2', 'lint')), {
        oneLine.body.node('1'),
      });
      expect(ci.of(effectAt('lib/ci.dart:2', 'test')), {
        oneLine.body.node('2'),
      });
      expect(
        ci.isIn(effectAt('lib/ci.dart:2', 'lint'), oneLine.body.node('2')!),
        isFalse,
      );
    });

    test('an effect whose name no node at its place has — the nodes name it by '
        'an expression — is at all of them', () {
      expect(ci.of(effectAt('lib/ci.dart:3', 'deploy-prod')), {
        oneLine.body.node('3'),
        oneLine.body.node('4'),
      });
    });

    test('an effect is at every node of its place and name: a finally drawn '
        'once for each way out of its try', () {
      final finallyTwice = GraphFunction(
        id: 'lib/f.dart#build',
        name: 'build',
        place: 'lib/f.dart:1',
        body: const GraphBody(
          nodes: [
            EffectNode(id: '1', place: 'lib/f.dart:5', name: 'clean'),
            EffectNode(id: '2', place: 'lib/f.dart:5', name: 'clean'),
          ],
          edges: [],
        ),
      );
      final places = EffectPlaces.of(finallyTwice, {
        finallyTwice.id: finallyTwice,
      });
      expect(places.of(effectAt('lib/f.dart:5', 'clean')), {
        finallyTwice.body.node('1'),
        finallyTwice.body.node('2'),
      });
    });

    test('an effect without a place, or at no node, is not on the graph', () {
      final places = effectPlacesOf('inPlace');
      expect(places.onGraph(effectAt(packagesAt(8))), isTrue);
      expect(places.onGraph(effectAt(packagesAt(99))), isFalse);
      expect(places.onGraph(effectAt(null)), isFalse);
      expect(places.onGraph(null), isFalse);
    });

    test('what a node holds: an effect itself; a call the effect nodes of its '
        'functions and deeper; a condition nothing', () {
      final places = effectPlacesOf('nested');
      final nested = file.functions['lib/packages.dart#nested']!.body;
      final prepare = file.functions['lib/packages.dart#prepare']!.body;
      expect(places.within(nodeOf(nested, '2')), {nodeOf(nested, '2')});
      expect(placesOf(places.within(nodeOf(nested, '1'))), {
        for (final line in [27, 30, 31, 34]) packagesAt(line),
      });
      expect(placesOf(places.within(nodeOf(prepare, '2'))), {
        packagesAt(30),
        packagesAt(31),
      });
      final viaCall = file.functions['lib/packages.dart#viaCall']!.body;
      expect(placesOf(effectPlacesOf('viaCall').within(nodeOf(viaCall, '1'))), {
        for (final line in [20, 21, 22]) packagesAt(line),
      });
      expect(
        places.within(
          const ConditionNode(
            id: 'c',
            place: 'lib/packages.dart:1',
            label: 'x',
          ),
        ),
        isEmpty,
      );
    });

    test('a called body: that of a function the workflow calls, not the '
        'workflow\'s own', () {
      final places = effectPlacesOf('viaCall');
      final viaCall = file.functions['lib/packages.dart#viaCall']!;
      expect(
        places.isCalled(file.functions['lib/packages.dart#publish']!.body),
        isTrue,
      );
      expect(places.isCalled(viaCall.body), isFalse);
      expect(places.isCalled(const GraphBody(nodes: [], edges: [])), isFalse);
    });

    test('a function calling itself holds its effects once', () {
      final recursive = GraphFunction(
        id: 'lib/r.dart#crawl',
        name: 'crawl',
        place: 'lib/r.dart:1',
        body: const GraphBody(
          nodes: [
            EffectNode(id: '1', place: 'lib/r.dart:2', name: 'visit'),
            CallNode(
              id: '2',
              place: 'lib/r.dart:3',
              functions: ['lib/r.dart#crawl'],
            ),
          ],
          edges: [],
        ),
      );
      final places = EffectPlaces.of(recursive, {recursive.id: recursive});
      expect(places.nodes, {recursive.body.node('1')});
      expect(places.within(recursive.body.node('2')!), {
        recursive.body.node('1'),
      });
    });

    test('isIn: whether an effect is on a node or inside it', () {
      final places = effectPlacesOf('inPlace');
      final body = file.functions['lib/packages.dart#inPlace']!.body;
      expect(places.isIn(effectAt(packagesAt(8)), nodeOf(body, '2')), isTrue);
      expect(places.isIn(effectAt(packagesAt(8)), nodeOf(body, '1')), isFalse);
      expect(places.isIn(effectAt(packagesAt(4)), nodeOf(body, '1')), isTrue);
      expect(places.isIn(effectAt(null), nodeOf(body, '1')), isFalse);
      expect(places.isIn(null, nodeOf(body, '1')), isFalse);
    });
  });

  group('the calls an effect ran in (callsIn)', () {
    final functions = decidingFunctions();
    final places = decidingPlaces();
    final develop = functions['lib/packages.dart#develop']!.body;
    final calls = {
      for (final (id, name) in [('1', 'setup'), ('2', 'design'), ('3', 'ship')])
        name: develop.node(id)!,
    };

    /// The calls of develop's body the effect [key] of [j] ran in.
    List<String> callsOf(Journal j, String key) {
      final session = j.data;
      final effect = session.effectWithKey(key);
      return [
        for (final MapEntry(key: name, value: call) in calls.entries)
          if (places.callsIn(session).isIn(effect, call)) name,
      ];
    }

    test('an effect of a graph several graphs call ran in the call that '
        'called it: the one the effects it follows by after lead into', () {
      final j = decidingSession();
      expect(callsOf(j, 'w'), ['setup']);
      for (final key in ['b1', 'p1', 'a1', 'b2', 'p2', 'a2']) {
        expect(callsOf(j, key), ['design'], reason: key);
      }
      final asked = decidingSession(setupAsks: true);
      expect(callsOf(asked, 'p0'), ['setup']);
      expect(callsOf(asked, 'a0'), ['setup']);
      expect(callsOf(asked, 'p1'), ['design']);
    });

    test('and in that call alone inside the functions it calls', () {
      final session = decidingSession().data;
      final inDesign = functions['lib/packages.dart#design']!.body.node('2')!;
      final inSetup = functions['lib/packages.dart#setup']!.body.node('2')!;
      final answer = session.effectWithKey('a1');
      expect(places.callsIn(session).isIn(answer, inDesign), isTrue);
      expect(places.callsIn(session).isIn(answer, inSetup), isFalse);
    });

    test('with no effect before it on the graph to tell, in each of the '
        'calls', () {
      final j = Journal('d1d1-session', workflow: 'develop')
        ..effect('pose', 1, place: packagesAt(53), key: 'p', after: null)
        ..effect('pose', 2, place: packagesAt(53), key: 'q', after: 'gone')
        ..effect('lint', 3, place: 'lib/ci.dart:9', key: 'l', after: 'b')
        ..effect('pose', 4, place: packagesAt(53), key: 'r', after: 'l')
        // A ring of afters, as reruns may leave.
        ..effect('pose', 5, place: packagesAt(53), key: 's', after: 't')
        ..effect('answer', 6, place: packagesAt(54), key: 't', after: 's');
      for (final key in ['p', 'q', 'r', 's', 't']) {
        expect(callsOf(j, key), ['setup', 'design', 'ship'], reason: key);
      }
      expect(callsOf(j, 'l'), isEmpty);
    });

    test('an effect off the effects it follows still ran in the call they '
        'lead into', () {
      // lint is on no node; the pose after it follows design's brainstorm.
      final j = Journal('d1d1-session', workflow: 'develop')
        ..effect('brainstorm', 1, place: packagesAt(48), key: 'b', after: null)
        ..effect('lint', 2, place: 'lib/ci.dart:9', key: 'l', after: 'b')
        ..effect('pose', 3, place: packagesAt(53), key: 'p', after: 'l');
      expect(callsOf(j, 'p'), ['design']);
    });

    test('isInFunction: whether an effect ran in the body of a function the '
        'workflow reaches, or in what it calls', () {
      final session = decidingSession().data;
      final ran = places.callsIn(session);
      bool isIn(String key, String function) => ran.isInFunction(
        session.effectWithKey(key),
        'lib/packages.dart#$function',
      );
      expect(isIn('p1', 'design'), isTrue);
      expect(isIn('p1', 'decide'), isTrue);
      expect(isIn('p1', 'setup'), isFalse);
      expect(isIn('p1', 'ship'), isFalse);
      expect(isIn('w', 'setup'), isTrue);
      expect(isIn('w', 'develop'), isTrue);
      expect(isIn('w', 'gone'), isFalse);
      expect(ran.isInFunction(null, 'lib/packages.dart#setup'), isFalse);

      const publish = 'lib/packages.dart#publish';
      final viaCall = effectPlacesOf('viaCall').callsIn(session);
      expect(viaCall.isInFunction(effectAt(packagesAt(20)), publish), isTrue);
      expect(
        viaCall.isInFunction(effectAt(packagesAt(17), 'announce'), publish),
        isFalse,
      );
      expect(viaCall.isInFunction(effectAt(null), publish), isFalse);
      // inPlace calls ship, not publish: none of its effects are in it.
      expect(
        effectPlacesOf('inPlace')
            .callsIn(session)
            .isInFunction(effectAt(packagesAt(20)), publish),
        isFalse,
      );
    });
  });

  test('effectsNotOnGraph: the effects without a place or at no node, in '
      'order', () {
    final journal = Journal('a1b2-session', workflow: 'inPlace')
      ..effect('plan', 1, end: 2, place: packagesAt(4))
      ..effect('stray', 2, end: 3, place: 'lib/old.dart:3')
      ..effect('upload', 3, end: 4, place: packagesAt(7))
      ..effect('nowhere', 4);
    final effects = journal.data.effectsInOrder;
    expect(
      [
        for (final effect in effectsNotOnGraph(
          effects,
          effectPlacesOf('inPlace'),
        ))
          effect.name,
      ],
      ['stray', 'nowhere'],
    );
  });
}
