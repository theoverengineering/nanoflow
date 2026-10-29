import 'dart:math' as math;

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/layout/lanes.dart' show clearance;
import 'package:nanoflow_ui/layout/layout.dart';
import 'package:test/test.dart';

import 'random_graphs_test.dart' show randomBody;
import 'support.dart';

void main() {
  final release = loadGraphFile('release');
  final inline = loadGraphFile('inline');
  final recursion = loadGraphFile('recursion');
  final taskCarry = loadGraphFile('task-carry');
  final chain = loadGraphFile('chain');
  final chainLater = loadGraphFile('chain-later');

  /// release with its call of publish() expanded in place.
  GraphLayout releaseWithPublish() => layoutBody(
    functionOf(release, 'release').body,
    functions: release.functions,
    expanded: {'5': ExpandedNode(functionOf(release, 'publish').body)},
  );

  /// viaCall with its call of publishEach() expanded, and in it the call of
  /// publish().
  GraphLayout callInCall() => layoutBody(
    functionOf(inline, 'viaCall').body,
    functions: inline.functions,
    expanded: {
      '1': ExpandedNode(
        functionOf(inline, 'publishEach').body,
        expanded: {'1': ExpandedNode(functionOf(inline, 'publish').body)},
      ),
    },
  );

  /// crawl with visit() expanded in it, and crawl() in that.
  GraphLayout crawlInCrawl() => layoutBody(
    functionOf(recursion, 'crawl').body,
    functions: recursion.functions,
    expanded: {
      '3': ExpandedNode(
        functionOf(recursion, 'visit').body,
        expanded: {'2': ExpandedNode(functionOf(recursion, 'crawl').body)},
      ),
    },
  );

  /// task with its call of carry() expanded in place: carry's loop comes
  /// back from work(), review() and decide(), the last nodes before its
  /// end.
  GraphLayout taskWithCarry() => layoutBody(
    functionOf(taskCarry, 'task').body,
    functions: taskCarry.functions,
    expanded: {'1': ExpandedNode(functionOf(taskCarry, 'carry').body)},
  );

  /// [taskWithCarry] with work() drawn in place in carry() too: the layer of
  /// work(), review() and decide() is as wide as work()'s frame.
  GraphLayout taskWithWork() => layoutBody(
    functionOf(taskCarry, 'task').body,
    functions: taskCarry.functions,
    expanded: {
      '1': ExpandedNode(
        functionOf(taskCarry, 'carry').body,
        expanded: {'3': ExpandedNode(functionOf(taskCarry, 'work').body)},
      ),
    },
  );

  /// lead with its call of judgeSpec() drawn in place (chain.graph.json,
  /// lib/chain.dart:242): judgeSpec's ways out — its returns from the
  /// `switch (decision.choice)`, the `while (refused != null)` loop, the
  /// `!answer.goesOn` forks — come to the end of its body from far back.
  GraphLayout leadWithJudgeSpec() => layoutBody(
    functionOf(chain, 'lead').body,
    functions: chain.functions,
    expanded: {'6': ExpandedNode(functionOf(chain, 'judgeSpec').body)},
  );

  /// chain with its call of lead() drawn in place, and judgeSpec() in that.
  GraphLayout chainWithJudgeSpec() => layoutBody(
    functionOf(chain, 'chain').body,
    functions: chain.functions,
    expanded: {
      '1': ExpandedNode(
        functionOf(chain, 'lead').body,
        expanded: {'6': ExpandedNode(functionOf(chain, 'judgeSpec').body)},
      ),
    },
  );

  /// lead with its call of cut() drawn in place (chain.graph.json,
  /// lib/chain.dart:349): four of cut's ways out come to the end of its
  /// body along a band over it.
  GraphLayout leadWithCut() => layoutBody(
    functionOf(chain, 'lead').body,
    functions: chain.functions,
    expanded: {'7': ExpandedNode(functionOf(chain, 'cut').body)},
  );

  /// chain with its call of lead() drawn in place, and cut() in that.
  GraphLayout chainWithCut() => layoutBody(
    functionOf(chain, 'chain').body,
    functions: chain.functions,
    expanded: {
      '1': ExpandedNode(
        functionOf(chain, 'lead').body,
        expanded: {'7': ExpandedNode(functionOf(chain, 'cut').body)},
      ),
    },
  );

  /// A fork before g() drawn in place, whose ways back leave under its way
  /// in: check's `ok` goes into g(), a fork of three effects, and its
  /// `retry` and `start over…` back to prepare.
  GraphLayout forkBeforeFrame() => layoutBody(
    const GraphBody(
      nodes: [
        EffectNode(id: 'b', place: 'lib/a.dart:2', name: 'prepare'),
        ConditionNode(id: 'a', place: 'lib/a.dart:3', label: 'check'),
        CallNode(id: 'f', place: 'lib/a.dart:4', functions: ['lib/a.dart#g']),
      ],
      edges: [
        GraphEdge(from: null, to: 'b', label: null),
        GraphEdge(from: 'b', to: 'a', label: null),
        GraphEdge(from: 'a', to: 'f', label: 'ok'),
        GraphEdge(from: 'a', to: 'b', label: 'retry'),
        GraphEdge(from: 'a', to: 'b', label: 'start over with a fresh token'),
        GraphEdge(from: 'f', to: null, label: null),
      ],
    ),
    expanded: {
      'f': ExpandedNode(
        bodyOf({
          'start': 'which',
          'nodes': {
            'which': {
              'decide': true,
              'then': {'x': 'one', 'y': 'two', 'z': 'three'},
            },
            'one': {'command': true, 'then': <Object?>[]},
            'two': {'command': true, 'then': <Object?>[]},
            'three': {'command': true, 'then': <Object?>[]},
          },
        }),
      ),
    },
  );

  group('publish() expanded inside release', () {
    late GraphLayout layout;
    late NodeBox call;
    late FrameBox frame;
    setUpAll(() {
      layout = releaseWithPublish();
      call = layout.nodes['5']!;
      frame = call.frame!;
    });

    test('the call is a frame round the layout of its function: its nodes '
        'between one start and one end, ports on the frame\'s sides with no '
        'tile', () {
      expect(frame.inner.nodes.keys, [
        startMarker,
        '1',
        '2',
        '3',
        '4',
        endMarker,
      ]);
      expect(layout.nodes['1']!.frame, isNull);
      final start = frame.inner.nodes[startMarker]!;
      final end = frame.inner.nodes[endMarker]!;
      for (final port in [start, end]) {
        expect(port.port, isTrue);
        expect(port.tile.width, 0);
      }
      expect(start.tile.left, call.tile.left);
      expect(end.tile.left, call.tile.right);
      expect(layout.nodes[startMarker]!.port, isFalse);
      expect(layout.nodes[endMarker]!.port, isFalse);
    });

    test('keeps every rule of step 9, in the frame too', () {
      expect(checkLayout(layout), isEmpty);
      expect(checkLayout(frame.inner), isEmpty);
    });

    test('the body sits in the frame under its title row, from side to '
        'side, with room under it', () {
      const room = FrameRoom();
      final tile = call.tile;
      final body = frame.inner.bounds;
      expect(body.left, closeTo(tile.left, 1e-9));
      expect(body.right, closeTo(tile.right, 1e-9));
      expect(body.top - tile.top, closeTo(room.top, 1e-9));
      expect(tile.bottom - body.bottom, closeTo(room.bottom, 1e-9));
      for (final node in frame.inner.nodes.values) {
        for (final rect in [node.tile, node.nameRect, node.placeRect]) {
          expect(_within(rect, body), isTrue, reason: node.id);
        }
      }
      for (final edge in frame.inner.edges) {
        expect(edge.points.every((p) => _holds(body, p)), isTrue);
      }
      // The frame has no name or place under it: its title is in it.
      expect(call.nameRect.width, 0);
      expect(call.placeRect.width, 0);
    });

    test('no node overlaps the frame, and only the arrows into it and out '
        'of it reach its border', () {
      for (final node in layout.nodes.values) {
        if (node.id == '5') continue;
        for (final rect in [node.tile, node.nameRect, node.placeRect]) {
          expect(rect.overlaps(call.tile), isFalse, reason: node.id);
        }
      }
      for (final edge in layout.edges) {
        final touches = _borderTouches(edge, call.tile);
        if (edge.from == '5') {
          // It leaves from the right side, where the end is.
          expect(touches, [edge.points.first], reason: '$edge');
          expect(edge.points.first.x, call.tile.right);
        } else {
          expect(touches, isEmpty, reason: '${edge.from}->${edge.to}');
        }
      }
      expect(layout.edges.where((e) => e.to == '5'), isNotEmpty);
    });

    test('arrows come in level with the start and go on from the frame\'s '
        'left side to the first node; the arrows to the end come to its '
        'right side, where those out of the frame leave', () {
      final start = frame.inner.nodes[startMarker]!.tile;
      final end = frame.inner.nodes[endMarker]!;
      expect(frame.entry!.a, frame.entry!.b, reason: 'nothing to link');
      final into = frame.inner.edges.where((e) => e.from == startMarker);
      expect(into.single.points.first, Point(call.tile.left, start.center.y));
      expect(into.single.to, '1');
      final o = layout.options;
      final entry =
          o.minInputStraight + o.arrowLength + o.arrowGap + o.barWidth / 2;
      expect(
        frame.inner.nodes['1']!.tile.left - call.tile.left,
        closeTo(entry, 1e-9),
        reason: 'the first node is as near the side as an arrow lets it',
      );
      for (final edge in frame.inner.edges.where((e) => e.to == endMarker)) {
        expect(edge.tip.x, call.tile.right - o.barWidth / 2 - o.arrowGap);
      }

      final bar = call.bar!;
      expect((bar.rect.top + bar.rect.bottom) / 2, closeTo(start.center.y, 0));
      for (final edge in layout.edges.where((e) => e.to == '5')) {
        expect(edge.tip.y, inInclusiveRange(bar.rect.top, bar.rect.bottom));
      }
      final out = layout.exits.where((x) => x.node == '5').single;
      expect(out.anchor, Point(call.tile.right, end.tile.center.y));
    });

    test('the start is first in the body and the end last, alone in their '
        'layers: nothing is between them and the frame\'s sides', () {
      final start = frame.inner.nodes[startMarker]!;
      final end = frame.inner.nodes[endMarker]!;
      for (final node in frame.inner.nodes.values) {
        if (node == start || node == end) continue;
        expect(node.layer, inExclusiveRange(start.layer, end.layer));
        expect(node.tile.left, greaterThan(start.tile.right), reason: node.id);
        expect(node.tile.right, lessThan(end.tile.left), reason: node.id);
      }
      for (final edge in frame.inner.edges) {
        for (final p in edge.points) {
          expect(p.x, inInclusiveRange(start.tile.right, end.tile.left));
        }
      }
    });

    test('is the same every time', () {
      expect(describe(releaseWithPublish()), describe(layout));
    });

    test('the end of the body is a bar on the frame\'s right side, as a '
        'tile\'s input bar: the false way of !ok and rollback point at it '
        'each at its own height, and the way out leaves its middle', () {
      _expectEndBar(layout, '5', ways: 2);
      expect(checkLayout(layout), isEmpty);
    });
  });

  group('the end of a body in a frame', () {
    /// A body with three ways to its end: a fork's way straight there, and
    /// one through each of two effects.
    final threeWays = bodyOf({
      'start': 'pick',
      'nodes': {
        'pick': {
          'decide': true,
          'then': {'a': 'a', 'b': 'b', 'none': <Object?>[]},
        },
        'a': {'command': true, 'then': <Object?>[]},
        'b': {'command': true, 'then': <Object?>[]},
      },
    });

    /// release with its call of publish() drawn in place as [body], in a
    /// frame keeping [room].
    GraphLayout releaseWith(
      GraphBody body, [
      FrameRoom room = const FrameRoom(),
    ]) => layoutBody(
      functionOf(release, 'release').body,
      functions: release.functions,
      expanded: {'5': ExpandedNode(body, room: room)},
    );

    test('three ways: three arrows at their own heights round the bar\'s '
        'middle, the bar past the outer ones as a tile\'s', () {
      final layout = releaseWith(threeWays);
      _expectEndBar(layout, '5', ways: 3);
      expect(checkLayout(layout), isEmpty);
    });

    test('one way: the bar is as long as a tile\'s with one input', () {
      final layout = releaseWith(
        bodyOf({
          'start': 'a',
          'nodes': {
            'a': {'command': true, 'then': <Object?>[]},
          },
        }),
      );
      _expectEndBar(layout, '5', ways: 1);
      final end = layout.nodes['5']!.frame!.inner.nodes[endMarker]!.bar!;
      // plan, the first node of release, has one arrow in.
      final plan = layout.nodes['1']!.bar!;
      expect(plan.inputs, hasLength(1));
      expect(end.rect.height, closeTo(plan.rect.height, 1e-9));
      expect(checkLayout(layout), isEmpty);
    });

    test('a frame wider than its body: the arrows to the end run on to its '
        'right side, where the bar is', () {
      final layout = releaseWith(threeWays, const FrameRoom(width: 1200));
      final call = layout.nodes['5']!;
      expect(call.tile.width, closeTo(1200, 1e-9));
      _expectEndBar(layout, '5', ways: 3);
      expect(call.frame!.inner.bounds.right, closeTo(call.tile.right, 1e-9));
      expect(checkLayout(layout), isEmpty);
    });

    test('a name under the node before the end reaching past it: the arrow '
        'to the end runs on to the frame\'s side, where the bar is', () {
      const name = 'notify-every-subscriber-of-it';
      final layout = releaseWith(
        bodyOf({
          'start': 'x',
          'nodes': {
            'x': {'command': true, 'then': name},
            name: {'command': true, 'then': <Object?>[]},
          },
        }),
      );
      final frame = layout.nodes['5']!.frame!;
      final o = layout.options;
      final last = frame.inner.nodes[name]!;
      expect(
        last.nameRect.right,
        greaterThan(
          last.tile.right +
              o.minInputStraight +
              o.arrowLength +
              o.arrowGap +
              o.barWidth / 2,
        ),
        reason: 'the name reaches past where a straight arrow ends',
      );
      _expectEndBar(layout, '5', ways: 1);
      expect(checkLayout(layout), isEmpty);
    });

    group('a frame whose way out is a capsule, branches of Future.wait after '
        'the call: the bar spans the arrows out too', () {
      /// callThenWait([out]) with its call drawn in place as a body whose
      /// fork has [ways] ways straight to its end.
      GraphLayout waysInOut(int ways, int out) => layoutBody(
        callThenWait(out),
        expanded: {
          'c': ExpandedNode(
            bodyOf({
              'start': 'pick',
              'nodes': {
                'pick': {
                  'decide': true,
                  'then': {for (var i = 0; i < ways; i++) 'k$i': <Object?>[]},
                },
              },
            }),
          ),
        },
      );

      for (final (ways, out) in [(1, 2), (1, 3), (5, 2), (2, 5)]) {
        test('$ways ways in, $out arrows out', () {
          final layout = waysInOut(ways, out);
          expect(
            layout.exits.singleWhere((x) => x.node == 'c').shape,
            ExitShape.capsule,
          );
          _expectEndBar(layout, 'c', ways: ways);
          expect(checkLayout(layout), isEmpty);
        });
      }
    });

    test('a call drawn in place in a frame ends at a bar too', () {
      final layout = callInCall();
      _expectEndBar(layout, '1', ways: 1);
      _expectEndBar(layout.nodes['1']!.frame!.inner, '1', ways: 1);
      expect(checkLayout(layout), isEmpty);
    });
  });

  test('step 9 finds a frame whose body, link or end are off their places', () {
    final layout = releaseWithPublish();
    final call = layout.nodes['5']!;
    final frame = call.frame!;
    List<String> problemsWith(FrameBox moved, {Rect? tile}) => checkLayout(
      GraphLayout(
        nodes: {
          ...layout.nodes,
          '5': NodeBox(
            id: call.id,
            kind: call.kind,
            node: call.node,
            name: call.name,
            fullName: call.fullName,
            place: call.place,
            inside: call.inside,
            layer: call.layer,
            tile: tile ?? call.tile,
            nameRect: call.nameRect,
            placeRect: call.placeRect,
            marks: call.marks,
            status: call.status,
            bar: call.bar,
            frame: moved,
          ),
        },
        exits: layout.exits,
        edges: layout.edges,
        bounds: layout.bounds,
        options: layout.options,
      ),
    );
    Segment lower(Segment s) =>
        Segment(s.a + const Point(0, 9), s.b + const Point(0, 9));

    expect(
      problemsWith(FrameBox(inner: frame.inner, entry: lower(frame.entry!))),
      containsAll([
        '5: bar is not level with the start in the frame',
        '5: the link to the start is off its place',
      ]),
    );
    final t = call.tile;
    expect(
      problemsWith(
        FrameBox(inner: frame.inner, entry: frame.entry),
        tile: Rect.fromLTRB(t.left, t.top, t.right + 9, t.bottom),
      ),
      contains('5: the end is off the frame\'s right side'),
    );
    expect(
      problemsWith(FrameBox(inner: layoutOf('release'), entry: null)),
      containsAll([
        '5: the body is not in the frame',
        '5: the body has several ends',
      ]),
    );
  });

  test('step 9 finds an arrow of the body running along a side of its '
      'frame nearer than the outline and a clearance', () {
    final layout = taskWithCarry();
    final call = layout.nodes['1']!;
    final tile = call.tile;
    final frame = call.frame!;
    final inner = frame.inner;
    final back = inner.edges.singleWhere(
      (e) => e.from == '3' && e.kind == EdgeKind.back,
    );
    final (down, _, _) = verticals(back).first;
    final lane = back.points.map((p) => p.y).reduce(math.max);
    // The problems of the layout with the arrow back from work() moved.
    List<String> problemsWith(Point Function(Point) move) => checkLayout(
      _withFrame(
        layout,
        '1',
        FrameBox(
          inner: GraphLayout(
            nodes: inner.nodes,
            exits: inner.exits,
            edges: [
              for (final e in inner.edges)
                identical(e, back) ? _moved(e, move, layout.options) : e,
            ],
            bounds: inner.bounds,
            options: inner.options,
          ),
          entry: frame.entry,
        ),
      ),
    );

    // Its way down on the right side, and just inside it.
    for (final gap in [0.0, sideClearance - 0.5]) {
      expect(
        problemsWith((p) => p.x == down ? Point(tile.right - gap, p.y) : p),
        contains(
          '1: 3#0.0->2 runs along the frame\'s right side '
          '${gap.toStringAsFixed(1)} from it',
        ),
      );
    }
    expect(
      problemsWith(
        (p) => p.x == down ? Point(tile.right - sideClearance, p.y) : p,
      ),
      isNot(contains(contains('runs along'))),
    );
    // Its lane under the body, near the bottom.
    expect(
      problemsWith((p) => p.y == lane ? Point(p.x, tile.bottom - 4) : p),
      contains('1: 3#0.0->2 runs along the frame\'s bottom side 4.0 from it'),
    );
  });

  test('step 9 finds an arrow of the level running along a side of a '
      'frame in it nearer than a clearance', () {
    final layout = forkBeforeFrame();
    final tile = layout.nodes['f']!.tile;
    final back = edgeOf(layout, 'a', 1);
    final (down, _, _) = verticals(back).first;
    // The problems of the layout with retry's way back moved.
    List<String> problemsWith(Point Function(Point) move) => checkLayout(
      GraphLayout(
        nodes: layout.nodes,
        exits: layout.exits,
        edges: [
          for (final e in layout.edges)
            identical(e, back) ? _moved(e, move, layout.options) : e,
        ],
        bounds: layout.bounds,
        options: layout.options,
      ),
    );

    // Its way down on the frame's left side, and just before it.
    for (final gap in [0.0, clearance - 0.5]) {
      expect(
        problemsWith((p) => p.x == down ? Point(tile.left - gap, p.y) : p),
        contains(
          'f: a#1.0->b runs outside along the frame\'s left side '
          '${gap.toStringAsFixed(1)} from it',
        ),
      );
    }
    expect(
      problemsWith((p) => p.x == down ? Point(tile.left - clearance, p.y) : p),
      isNot(contains(contains('runs outside along'))),
    );
  });

  group('check\'s ways back to prepare, leaving under its way into g() drawn '
      'in place', () {
    late GraphLayout layout;
    setUpAll(() => layout = forkBeforeFrame());

    test('keeps every rule of step 9', () {
      expect(checkLayout(layout), isEmpty);
    });

    test('go down a lane gap apart before the frame, the outer a clearance '
        'off its left side, which runs all the frame\'s height', () {
      final tile = layout.nodes['f']!.tile;
      final downs = [
        for (final exit in [1, 2]) verticals(edgeOf(layout, 'a', exit)).first,
      ];
      for (final (_, top, bottom) in downs) {
        // It passes the frame's heights down to its lane under check, not
        // under the frame.
        expect(top, greaterThan(tile.top));
        expect(bottom, lessThan(tile.bottom));
      }
      final xs = [for (final (x, _, _) in downs) x]..sort();
      expect(tile.left - xs.last, closeTo(clearance, 1e-9));
      expect(xs.last - xs.first, closeTo(layout.options.laneGap, 1e-9));
    });
  });

  group('carry() drawn in place in task, its loop coming back from the '
      'last nodes before its end', () {
    late GraphLayout layout;
    late NodeBox call;
    setUpAll(() {
      layout = taskWithCarry();
      call = layout.nodes['1']!;
    });

    test('keeps every rule of step 9, in the frame too', () {
      expect(checkLayout(layout), isEmpty);
    });

    test('the back arrows of work(), review() and decide() go down a lane '
        'gap apart, the outermost the outline and a clearance inside the '
        'frame\'s right side, where the end is', () {
      final inner = call.frame!.inner;
      final downs = [
        for (final id in ['3', '4', '5'])
          verticals(
            inner.edges.singleWhere(
              (e) => e.from == id && e.kind == EdgeKind.back,
            ),
          ).first.$1,
      ]..sort();
      expect(call.tile.right - downs.last, closeTo(sideClearance, 1e-9));
      for (var i = 1; i < downs.length; i++) {
        expect(downs[i] - downs[i - 1], closeTo(layout.options.laneGap, 1e-9));
      }
      expect(inner.nodes[endMarker]!.tile.left, call.tile.right);
    });

    test('the end is a bar on the frame\'s right side, the way out leaving '
        'its middle', () {
      _expectEndBar(layout, '1', ways: 1);
    });
  });

  group('work() drawn in place in carry() too, review() and decide() under '
      'its frame in one layer', () {
    late GraphLayout layout;
    late GraphLayout carry;
    setUpAll(() {
      layout = taskWithWork();
      carry = layout.nodes['1']!.frame!.inner;
    });

    test('keeps every rule of step 9, in the frames too', () {
      expect(checkLayout(layout), isEmpty);
    });

    test('crosses no more than with work() a tile', () {
      expect(
        countCrossings(carry),
        lessThanOrEqualTo(
          countCrossings(taskWithCarry().nodes['1']!.frame!.inner),
        ),
      );
    });

    test('the back arrows of review() and decide() go down next to their '
        'tiles, a clearance past their labels and the texts under them, '
        'decide()\'s inside review()\'s; work()\'s next to its frame', () {
      (double, double) down(String id) {
        final (x, _, lane) = verticals(
          carry.edges.singleWhere(
            (e) => e.from == id && e.kind == EdgeKind.back,
          ),
        ).first;
        return (x, lane);
      }

      final frame = carry.nodes['3']!.tile;
      expect(carry.nodes['4']!.tile.right, lessThan(frame.right - 1000));
      final (decide, decideLane) = down('5');
      final (review, reviewLane) = down('4');
      final (work, workLane) = down('3');
      expect(decide, closeTo(turnDownBeside(carry, '5', 0), 1e-9));
      expect(review, closeTo(decide + layout.options.laneGap, 1e-9));
      expect(work, closeTo(turnDownBeside(carry, '3', 0), 1e-9));
      expect(decideLane, lessThan(reviewLane));
      expect(reviewLane, lessThan(workLane));
    });
  });

  group('judgeSpec() drawn in place in lead, its ways to its end coming from '
      'far back', () {
    for (final (view, lay, path) in [
      ('in lead', leadWithJudgeSpec, ['6']),
      ('in lead in chain', chainWithJudgeSpec, ['1', '6']),
    ]) {
      late GraphLayout layout;
      late GraphLayout body;
      setUpAll(() {
        layout = lay();
        body = layout;
        for (final id in path) {
          body = body.nodes[id]!.frame!.inner;
        }
      });

      test('$view: keeps every rule of step 9, in the frames too', () {
        expect(checkLayout(layout), isEmpty);
      });

      test('$view: every arrow to the end runs straight into the bar, none '
          'jogging just before it; it turns once, to its input\'s height, '
          'but for the ways out of the switch\'s commit or stop, of rounds '
          '>= maxRounds and of ask: dispute, which go down round the nodes '
          'under the switch and come up to it', () {
        final bar = body.nodes[endMarker]!.bar!;
        final arrows = body.edges.where((e) => e.to == endMarker).toList();
        expect(arrows, hasLength(8));
        expect(jogsBeforeEnd(body), isEmpty);
        const round = {'10#2', '17#1', '18#0'};
        for (final edge in arrows) {
          final name = '${edge.from}#${edge.exitIndex}';
          final turns = turnsOf(edge);
          expect(bar.inputs, contains(edge.points.last.y), reason: name);
          if (turns.isEmpty) continue;
          expect(turns.last.to, edge.points.last.y, reason: name);
          expect(
            turns,
            hasLength(round.contains(name) ? 2 : 1),
            reason: '$name: ${edge.points}',
          );
          if (round.contains(name)) {
            expect(turns.first.to, greaterThan(turns.last.to), reason: name);
          }
        }
      });
    }
  });

  for (final (view, lay, path) in [
    ('in lead', leadWithCut, ['7']),
    ('in lead in chain', chainWithCut, ['1', '7']),
  ]) {
    test('cut() drawn in place $view: every arrow to its end turns at most '
        'once, to its input\'s height, and runs straight into the bar, but '
        'for the true of the first !answer.goesOn and the false of !posted, '
        'which jog into it: their forks stand with true above false', () {
      final layout = lay();
      var body = layout;
      for (final id in path) {
        body = body.nodes[id]!.frame!.inner;
      }
      expect(checkLayout(layout), isEmpty);
      final arrows = body.edges.where((e) => e.to == endMarker).toList();
      expect(arrows, isNotEmpty);
      const jogging = {'4#0', '13#1'};
      for (final edge in arrows) {
        final name = '${edge.from}#${edge.exitIndex}';
        expect(
          turnsOf(edge).length,
          lessThanOrEqualTo(jogging.contains(name) ? 2 : 1),
          reason: '$name: ${edge.points}',
        );
      }
      expect({
        for (final jog in jogsBeforeEnd(body)) jog.split(' ').first,
      }, jogging);
    });
  }

  test('specify() drawn in place in lead, and judgeSpec() in it '
      '(chain-later.graph.json): every arrow to either end turns at most '
      'once and runs straight into the bar — but in judgeSpec() the true of '
      'judged.verdict == \'PASS\' and the false of failed >= maxRounds, '
      'whose forks stand with true above false —, and the height that takes '
      'is paid for by the turns it saves', () {
    GraphLayout lay() => layoutBody(
      functionOf(chainLater, 'lead').body,
      functions: chainLater.functions,
      expanded: {
        '4': ExpandedNode(
          functionOf(chainLater, 'specify').body,
          expanded: {
            '7': ExpandedNode(functionOf(chainLater, 'judgeSpec').body),
          },
        ),
      },
    );
    final layout = lay();
    expect(checkLayout(layout), isEmpty);
    final specify = layout.nodes['4']!.frame!.inner;
    final judgeSpec = specify.nodes['7']!.frame!.inner;
    // The arrows that turn more: the true of judged.verdict == 'PASS'
    // climbs over failed >= maxRounds and comes down to the end, and the
    // false of failed >= maxRounds goes round ask: dispute, under it.
    const more = {'judgeSpec 8#0': 3, 'judgeSpec 9#1': 2};
    for (final (name, body) in [
      ('specify', specify),
      ('judgeSpec', judgeSpec),
    ]) {
      expect(unheldJogs(body), isEmpty, reason: name);
      for (final edge in body.edges.where((e) => e.to == endMarker)) {
        final arrow = '$name ${edge.from}#${edge.exitIndex}';
        expect(
          turnsOf(edge).length,
          lessThanOrEqualTo(more[arrow] ?? 1),
          reason: '$arrow: ${edge.points}',
        );
      }
    }
    // The tightest trade the guard has to let through, with a wide margin:
    // docs/graph-layout.md §6 «Узел с несколькими входами» has its numbers.
    final before = _asBefore(lay);
    final now = deepTurns(layout);
    final was = deepTurns(before);
    final saved = was.turns - now.turns + 2 * (was.twice - now.twice);
    final grows = layout.bounds.height - before.bounds.height;
    expect(saved, greaterThan(0));
    expect(grows, lessThanOrEqualTo(layout.options.tile / 2 * saved + 1e-6));
    expect(grows / saved, lessThan(layout.options.tile / 2 / 8));
  });

  for (final function in ['write', 'decide', 'work']) {
    test('$function() of chain-later drawn in place: no arrow that turned '
        'before turns again just before its end', () {
      final drawn = inPlace(
        functionOf(chainLater, function).body,
        functions: chainLater.functions,
      );
      expect(checkLayout(drawn), isEmpty);
      final body = drawn.nodes['c']!.frame!.inner;
      expect(jogsBeforeEnd(body), isEmpty);
    });
  }

  for (final (function, fork) in [
    ('writeCut', 'account == null'),
    ('review', 'failed >= maxRounds'),
  ]) {
    test('$function() of chain-later drawn in place: only the true of the '
        'first !answer.goesOn and the false of $fork turn again just before '
        'its end — their forks stand with true above false, the end between '
        'them', () {
      final drawn = inPlace(
        functionOf(chainLater, function).body,
        functions: chainLater.functions,
      );
      expect(checkLayout(drawn), isEmpty);
      final body = drawn.nodes['c']!.frame!.inner;
      expect(
        {for (final jog in jogsBeforeEnd(body)) jog.split(' ').first},
        {'4#0', '12#1'},
      );
      expect(unheldJogs(body), isEmpty);
    });
  }

  test('write() of chain-later drawn in place: every arrow into its end '
      'turns once, to its input\'s height, past what stands in its way — '
      'but the true of the first !answer.goesOn, a fork with true above '
      'false, which turns twice', () {
    final drawn = inPlace(
      functionOf(chainLater, 'write').body,
      functions: chainLater.functions,
    );
    final body = drawn.nodes['c']!.frame!.inner;
    final arrows = body.edges.where((e) => e.to == endMarker).toList();
    expect(arrows, hasLength(5));
    for (final edge in arrows) {
      final name = '${edge.from}#${edge.exitIndex}';
      expect(
        turnsOf(edge).length,
        lessThanOrEqualTo(name == '4#0' ? 2 : 1),
        reason: '$name: ${edge.points}',
      );
    }
  });

  test('work() drawn in place in carry() in task (chain-later): the arrow from '
      'the first !answer.goesOn turns once, to its input\'s height, and runs '
      'straight into the bar; move\'s turns twice at most', () {
    final task = layoutBody(
      functionOf(chainLater, 'task').body,
      functions: chainLater.functions,
      expanded: {
        '1': ExpandedNode(
          functionOf(chainLater, 'carry').body,
          expanded: {'5': ExpandedNode(functionOf(chainLater, 'work').body)},
        ),
      },
    );
    expect(checkLayout(task), isEmpty);
    final work = task.nodes['1']!.frame!.inner.nodes['5']!.frame!.inner;
    EdgePath into(String from) =>
        work.edges.singleWhere((e) => e.from == from && e.to == endMarker);
    final first = into('4');
    final turns = turnsOf(first);
    expect(turns, hasLength(1), reason: '$turns');
    expect(turns.single.to, first.points.last.y);
    expect(turnsOf(into('24')).length, lessThanOrEqualTo(2));
  });

  test('finish() of chain-later, drawn in place and in lead: the way out of '
      'while (notGathered != null) keeps its two turns, no third one for '
      'the end standing level with report', () {
    final inPlaceBody = inPlace(
      functionOf(chainLater, 'finish').body,
      functions: chainLater.functions,
    ).nodes['c']!.frame!.inner;
    final lead = layoutBody(
      functionOf(chainLater, 'lead').body,
      functions: chainLater.functions,
      expanded: {'11': ExpandedNode(functionOf(chainLater, 'finish').body)},
    );
    final inLead = lead.nodes['11']!.frame!.inner;
    for (final body in [inPlaceBody, inLead]) {
      final arrow = body.edges.singleWhere(
        (e) => e.from == '17' && e.exitIndex == 1 && e.to == endMarker,
      );
      expect(
        turnsOf(arrow).length,
        lessThanOrEqualTo(2),
        reason: '${arrow.points}',
      );
    }
  });

  test('every function of the test graphs drawn in place: the end of its '
      'body stands where no more of its arrows would come in level — no '
      'arrows jogging into it by one height outnumber those coming in '
      'level, which hold it', () {
    var ends = 0;
    final fallbacks = levelInputFallbacks;
    final snaps = endSnapFallbacks;
    for (final name in graphNames()) {
      final file = loadGraphFile(name);
      for (final MapEntry(key: id, value: body) in bodiesOf(file).entries) {
        final drawn = inPlace(body, functions: file.functions);
        final inner = drawn.nodes['c']!.frame!.inner;
        if (inner.nodes[endMarker] != null) ends++;
        expect(unheldJogs(inner), isEmpty, reason: '$name $id');
      }
    }
    expect(ends, greaterThan(60));
    expect(endSnapFallbacks - snaps, 0);
    expect(
      levelInputFallbacks - fallbacks,
      0,
      reason:
          'no level of the test graphs crosses more with its nodes where '
          'most arrows come in level',
    );
  });

  group('two levels nested', () {
    for (final (name, lay, outer, inner) in [
      ('publish() in publishEach()', callInCall, '1', '1'),
      ('crawl() in visit() in crawl', crawlInCrawl, '3', '2'),
    ]) {
      test('$name: each frame inside the one round it, every rule kept', () {
        final layout = lay();
        final first = layout.nodes[outer]!;
        final second = first.frame!.inner.nodes[inner]!;
        expect(second.frame, isNotNull);
        expect(checkLayout(layout), isEmpty);
        expect(_within(second.tile, first.frame!.inner.bounds), isTrue);
        expect(
          _within(second.frame!.inner.bounds, second.tile),
          isTrue,
          reason: 'the inner body lies in its own frame',
        );
        for (final edge in first.frame!.inner.edges) {
          final touches = _borderTouches(edge, second.tile);
          expect(
            touches,
            edge.from == inner ? [edge.points.first] : isEmpty,
            reason: '${edge.from}->${edge.to}',
          );
        }
        expect(describe(lay()), describe(layout));
      });
    }
  });

  test('a frame keeps the room it is given: its title row, its sides, its '
      'bottom, its least width', () {
    const room = FrameRoom(top: 70, side: 24, bottom: 30, width: 1200);
    final layout = layoutBody(
      functionOf(release, 'release').body,
      functions: release.functions,
      expanded: {
        '5': ExpandedNode(functionOf(release, 'publish').body, room: room),
      },
    );
    final call = layout.nodes['5']!;
    final frame = call.frame!;
    final body = frame.inner.bounds;
    expect(call.tile.width, closeTo(1200, 1e-9));
    expect(body.top - call.tile.top, 70);
    expect(call.tile.bottom - body.bottom, 30);
    // A body narrower than the frame starts at its left side; the arrows to
    // its end run on to the right side.
    expect(body.left, call.tile.left);
    final end = frame.inner.nodes[endMarker]!.tile;
    expect(end.right, call.tile.right);
    expect(checkLayout(layout), isEmpty);
  });

  test('only calls expand; ids the body does not have are left out', () {
    final layout = layoutBody(
      functionOf(release, 'release').body,
      functions: release.functions,
      expanded: {
        '1': ExpandedNode(functionOf(release, 'publish').body),
        'missing': ExpandedNode(functionOf(release, 'publish').body),
      },
    );
    expect(
      describe(layout),
      describe(layoutOf('release')),
      reason: 'an effect does not expand',
    );
  });

  test('a body without a start or an end: the arrows go to the middle of '
      'the frame, and nothing links them in', () {
    const nowhere = GraphBody(
      nodes: [EffectNode(id: 'a', place: null, name: 'a')],
      edges: [],
    );
    final layout = layoutBody(
      functionOf(release, 'release').body,
      functions: release.functions,
      expanded: {'5': const ExpandedNode(nowhere)},
    );
    final call = layout.nodes['5']!;
    expect(call.frame!.entry, isNull);
    expect(call.frame!.endBar, isNull);
    final body = call.frame!.inner.bounds;
    const room = FrameRoom();
    expect(body.left - call.tile.left, closeTo(room.side, 1e-9));
    expect(call.tile.right - body.right, closeTo(room.side, 1e-9));
    final bar = call.bar!.rect;
    expect((bar.top + bar.bottom) / 2, closeTo(call.tile.center.y, 1e-9));
    expect(checkLayout(layout), isEmpty);
  });

  test('nodes nothing leads to in a body in a frame stand after its start, '
      'which nothing comes back to', () {
    // n4 comes back to n1, which nothing else leads to.
    final inner = GraphBody(
      nodes: [
        for (final id in ['n0', 'n1', 'n4'])
          EffectNode(id: id, place: null, name: id),
      ],
      edges: const [
        GraphEdge(from: null, to: 'n0', label: null),
        GraphEdge(from: 'n1', to: 'n4', label: null),
        GraphEdge(from: 'n4', to: 'n1', label: null),
        GraphEdge(from: 'n0', to: null, label: null),
      ],
    );
    final layout = layoutBody(
      functionOf(release, 'release').body,
      functions: release.functions,
      expanded: {'5': ExpandedNode(inner)},
    );
    final frame = layout.nodes['5']!.frame!;
    expect(frame.inner.nodes[startMarker]!.layer, 0);
    expect(frame.inner.nodes['n1']!.layer, 1);
    expect(checkLayout(layout), isEmpty);
  });

  test('random bodies with random nodes expanded, nested, in frames of '
      'random widths, keep step 9 but for loops in capsules; arrows out of '
      'nodes narrower than their layer turn next to them, crossing no more '
      'than past the layer', () {
    // Frames whose body has an arrow going back or round from a node just
    // before its end: its lane is next to the frame's right side.
    var backBeforeEnd = 0;
    // Arrows out of a node narrower than its layer turning before the
    // layer's right side.
    var turnedEarly = 0;
    // At every depth: no arrow of a level touches a frame in it but those
    // into it and out of it.
    void visit(GraphLayout level, String where) {
      final layerRight = <int, double>{};
      for (final node in level.nodes.values) {
        layerRight[node.layer] = math.max(
          layerRight[node.layer] ?? node.tile.right,
          node.tile.right,
        );
      }
      for (final edge in level.edges) {
        final turns = verticals(edge);
        final from = level.nodes[edge.from]!;
        if (turns.isNotEmpty && turns.first.$1 < layerRight[from.layer]!) {
          turnedEarly++;
        }
      }
      for (final node in level.nodes.values) {
        final inner = node.frame?.inner;
        if (inner == null) continue;
        final at = '$where ${node.id}';
        final tile = node.tile;
        for (final edge in level.edges) {
          if (edge.from != node.id && edge.to != node.id) {
            expect(
              _borderTouches(edge, tile),
              isEmpty,
              reason: '$at: ${edge.from}->${edge.to}',
            );
          }
        }
        final end = inner.nodes[endMarker];
        if (end != null &&
            inner.edges.any(
              (e) =>
                  e.kind != EdgeKind.forward &&
                  inner.nodes[e.from]!.layer == end.layer - 1,
            )) {
          backBeforeEnd++;
        }
        visit(inner, '$at ›');
      }
    }

    final fallbacks = earlyTurnFallbacks;
    for (var seed = 0; seed < 150; seed++) {
      final layout = _randomNested(seed);
      expect(
        checkLayout(layout).where((p) => !p.contains('loop crosses')),
        isEmpty,
        reason: 'seed $seed',
      );
      visit(layout, 'seed $seed:');
    }
    expect(
      backBeforeEnd,
      greaterThan(0),
      reason: 'the lanes next to a frame\'s right side are tried',
    );
    expect(
      earlyTurnFallbacks - fallbacks,
      0,
      reason:
          'turning next to the nodes crosses no more and breaks no rule '
          'more often than turning past the layer',
    );
    expect(
      turnedEarly,
      greaterThanOrEqualTo(482),
      reason:
          'as many arrows turn next to a node narrower than its layer as '
          'when the turns came in: a turn passes only turns whose order '
          'with it does not change what crosses',
    );
  });

  test('random body 781 nested, n2 in n7: n6 stands where the arrow from n5 '
      'to the end still runs through its corridor in two turns, not a '
      'staircase', () {
    final body = _randomNested(781)
        .nodes['n7']!
        .frame!
        .inner
        .nodes['n2']!
        .frame!
        .inner;
    final arrow = body.edges.singleWhere(
      (e) => e.from == 'n5' && e.exitIndex == 0 && e.to == endMarker,
    );
    expect(
      turnsOf(arrow).length,
      lessThanOrEqualTo(2),
      reason: '${arrow.points}',
    );
  });

  test('random body 1577 nested: the level round the frame of n8, whose '
      'body changed, is laid out round it in the order chosen round it as it '
      'was and kept only if no worse, so it crosses no more and grows no '
      'taller', () {
    final level = _randomNested(1577).nodes['n8']!.frame!.inner;
    expect(countCrossings(level), 0);
    expect(level.bounds.height, lessThanOrEqualTo(1202));
  });

  for (final (seed, base) in [(603, 2347.0), (870, 2760.5)]) {
    test('random body $seed nested: it grows taller for nodes standing where '
        'more arrows come in level only by half a tile for each turn saved, '
        'counted twice for an arrow turning twice no more', () {
      // 603 would grow far for the turns it saves without the guard:
      // docs/graph-layout.md §6 «Узел с несколькими входами» has its numbers.
      final layout = _randomNested(seed);
      final before = _asBefore(() => _randomNested(seed));
      expect(before.bounds.height, closeTo(base, 1));
      final now = deepTurns(layout);
      final was = deepTurns(before);
      final saved = was.turns - now.turns + 2 * (was.twice - now.twice);
      expect(
        layout.bounds.height - before.bounds.height,
        lessThanOrEqualTo(layout.options.tile / 2 * saved + 1e-6),
        reason: 'saved $saved',
      );
    });
  }

  test('random bodies in frames, nested: the end of each body stands where '
      'no more of its arrows would come in level — no two arrows that '
      'turned before jog by one height into it while fewer come in without '
      'turning before it —, but where the guards kept the body as before', () {
    var ends = 0;
    var asBefore = 0;
    final fallbacks = levelInputFallbacks;
    final snaps = endSnapFallbacks;
    void visit(GraphLayout level, GraphLayout before, String where) {
      for (final node in level.nodes.values) {
        final inner = node.frame?.inner;
        if (inner == null) continue;
        final old = before.nodes[node.id]!.frame!.inner;
        if (inner.nodes[endMarker] != null) ends++;
        // Each group, its jog and the arrows without one too, as the layout
        // as before has it where the guards kept the body's heights.
        final jogs = unheldJogs(inner, least: 2);
        if (jogs.isNotEmpty &&
            unheldJogs(old, least: 2).toSet().containsAll(jogs)) {
          asBefore++;
        } else {
          expect(jogs, isEmpty, reason: '$where ${node.id}');
        }
        visit(inner, old, '$where ${node.id} ›');
      }
    }

    for (var seed = 0; seed < 150; seed++) {
      final layout = _randomNested(seed);
      final before = _asBefore(() => _randomNested(seed));
      visit(layout, before, 'seed $seed:');
    }
    expect(ends, greaterThan(500));
    expect(
      asBefore,
      0,
      reason:
          'with the arrows taking their input\'s height right past what '
          'stands in their way, no body keeps a group of jogs before its '
          'end, not even where the guards kept its heights as before',
    );
    expect(
      endSnapFallbacks - snaps,
      0,
      reason: 'no end snapped to its arrows here is worse for it',
    );
    expect(
      levelInputFallbacks - fallbacks,
      lessThanOrEqualTo(53),
      reason:
          'nodes stand where most of their arrows come in level only where '
          'the level — and round a frame whose body changed, the level '
          'round it — crosses no more, breaks no more rules, has no more '
          'turns, arrows turning twice or staircases, and grows no more '
          'than half a tile for each turn saved; of these random levels 53 '
          'keep the heights of before',
    );
  });
}

/// What [lay] lays out with every node level with the arrow from the
/// longest path into it, as before nodes stood where most of their arrows
/// come in level.
GraphLayout _asBefore(GraphLayout Function() lay) {
  levelInputsEnabled = false;
  try {
    return lay();
  } finally {
    levelInputsEnabled = true;
  }
}

/// The layout of random body [seed] with random nodes expanded, nested two
/// deep, in frames of random widths.
GraphLayout _randomNested(int seed) {
  Map<String, ExpandedNode> expand(GraphBody body, int salt, int depth) => {
    for (final (i, node) in body.nodes.indexed)
      if (node is CallNode && (seed + salt + i) % 3 != 0 && depth < 2)
        node.id: () {
          final inner = randomBody(seed * 31 + salt + i + 1);
          // Often wider than the body: its end goes on to the side.
          final width = (seed + salt + i) % 4 * 200.0;
          return ExpandedNode(
            inner,
            room: FrameRoom(width: width),
            expanded: expand(inner, salt + i + 7, depth + 1),
          );
        }(),
  };
  final body = randomBody(seed);
  return layoutBody(body, expanded: expand(body, 0, 0));
}

/// Expects the end of the body in the frame of the node [id] of [layout] to
/// be a bar as a tile's input bar, the [ways] arrows that end the body
/// pointing at it, and the frame's way out: its width's middle on the
/// frame's right side, its middle level with the end, where the arrows out
/// leave from; the arrows in at their own heights a port gap apart round
/// its middle, each an arrow gap and a head before it; the bar half a port
/// gap past the outermost arrow, in or out, never shorter than the least
/// bar — as a tile's bar is past its inputs.
void _expectEndBar(GraphLayout layout, String id, {required int ways}) {
  final o = layout.options;
  final call = layout.nodes[id]!;
  final end = call.frame!.inner.nodes[endMarker]!;
  final bar = end.bar!;
  final rect = bar.rect;
  expect(end.tile.left, closeTo(call.tile.right, 1e-9));
  expect((rect.left + rect.right) / 2, closeTo(call.tile.right, 1e-9));
  expect(rect.width, closeTo(o.barWidth, 1e-9));
  final middle = (rect.top + rect.bottom) / 2;
  expect(middle, closeTo(end.tile.center.y, 1e-9));
  for (final out in layout.exits.where((x) => x.node == id)) {
    expect(out.anchor, Point(call.tile.right, middle));
  }
  final ends = call.frame!.inner.edges.where((e) => e.to == endMarker);
  expect(ends, hasLength(ways));
  final heights = [for (final e in ends) e.tip.y]..sort();
  expect(bar.inputs, heights);
  for (var i = 1; i < heights.length; i++) {
    expect(heights[i] - heights[i - 1], closeTo(o.portGap, 1e-9));
  }
  expect((heights.first + heights.last) / 2, closeTo(middle, 1e-9));
  for (final edge in ends) {
    expect(edge.tip.x, closeTo(rect.left - o.arrowGap, 1e-9));
    expect(edge.tip.x - edge.points.last.x, closeTo(o.arrowLength, 1e-9));
    expect(edge.points.last.y, edge.tip.y);
  }
  final outs = [
    for (final e in layout.edges)
      if (e.from == id) e.points.first,
  ];
  for (final p in outs) {
    expect(p.x, closeTo(call.tile.right, 1e-9));
  }
  final reach = [
    for (final y in [...heights, for (final p in outs) p.y]) (y - middle).abs(),
  ].reduce(math.max);
  expect(rect.height, closeTo(math.max(o.minBar, 2 * reach + o.portGap), 1e-9));
}

/// [layout] with the frame of its node [id] replaced by [frame].
GraphLayout _withFrame(GraphLayout layout, String id, FrameBox frame) {
  final node = layout.nodes[id]!;
  return GraphLayout(
    nodes: {
      ...layout.nodes,
      id: NodeBox(
        id: node.id,
        kind: node.kind,
        node: node.node,
        name: node.name,
        fullName: node.fullName,
        place: node.place,
        inside: node.inside,
        layer: node.layer,
        tile: node.tile,
        nameRect: node.nameRect,
        placeRect: node.placeRect,
        marks: node.marks,
        status: node.status,
        bar: node.bar,
        frame: frame,
        port: node.port,
      ),
    },
    exits: layout.exits,
    edges: layout.edges,
    bounds: layout.bounds,
    options: layout.options,
  );
}

/// [edge] with its points moved by [move].
EdgePath _moved(
  EdgePath edge,
  Point Function(Point) move,
  LayoutOptions options,
) {
  final points = [for (final p in edge.points) move(p)];
  return EdgePath(
    from: edge.from,
    exitIndex: edge.exitIndex,
    listIndex: edge.listIndex,
    edgeIndex: edge.edgeIndex,
    to: edge.to,
    kind: edge.kind,
    points: points,
    tip: points.last + Point(options.arrowLength, 0),
    pieces: roundCorners(points, options.cornerRadius),
  );
}

/// Whether [inner] lies in [outer].
bool _within(Rect inner, Rect outer) =>
    inner.left >= outer.left - 1e-9 &&
    inner.top >= outer.top - 1e-9 &&
    inner.right <= outer.right + 1e-9 &&
    inner.bottom <= outer.bottom + 1e-9;

bool _holds(Rect rect, Point p) =>
    p.x >= rect.left - 1e-9 &&
    p.x <= rect.right + 1e-9 &&
    p.y >= rect.top - 1e-9 &&
    p.y <= rect.bottom + 1e-9;

/// The points of [edge] on the border of [frame], and where its pieces
/// cross that border or run in it.
List<Point> _borderTouches(EdgePath edge, Rect frame) {
  final corners = [
    Point(frame.left, frame.top),
    Point(frame.right, frame.top),
    Point(frame.right, frame.bottom),
    Point(frame.left, frame.bottom),
  ];
  final border = [
    for (var i = 0; i < 4; i++) Segment(corners[i], corners[(i + 1) % 4]),
  ];
  final touches = <Point>[];
  for (var i = 1; i < edge.points.length; i++) {
    final piece = Segment(edge.points[i - 1], edge.points[i]);
    if (piece.entersInterior(frame)) {
      touches.add(piece.a);
      continue;
    }
    for (final side in border) {
      if (piece.crosses(side) || _onSide(piece.a, side)) {
        if (!touches.contains(piece.a)) touches.add(piece.a);
      }
    }
  }
  return touches;
}

/// Whether [p] lies on [side].
bool _onSide(Point p, Segment side) {
  final along = Segment(side.a, p).length + Segment(p, side.b).length;
  return (along - side.length).abs() < 1e-6;
}
