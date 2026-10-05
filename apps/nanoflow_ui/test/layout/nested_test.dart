import 'dart:math' as math;

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/layout/layout.dart';
import 'package:test/test.dart';

import 'random_graphs_test.dart' show randomBody;
import 'support.dart';

void main() {
  final release = loadGraphFile('release');
  final inline = loadGraphFile('inline');
  final recursion = loadGraphFile('recursion');

  /// release with its call of publish() expanded in place.
  GraphLayout releaseWithPublish() => layoutBody(
    functionOf(release, 'release').body,
    functions: release.functions,
    expanded: {'5': ExpandedNode(functionOf(release, 'publish').body)},
  );

  /// viaCall with its copies expanded, and in them the call of publish().
  GraphLayout copiesWithCall() => layoutBody(
    functionOf(inline, 'viaCall').body,
    functions: inline.functions,
    expanded: {
      '1': ExpandedNode(
        (functionOf(inline, 'viaCall').body.node('1')! as CopiesNode).body,
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
      expect(frame.exit!.a, frame.exit!.b, reason: 'nothing to link');
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
      final frame = call.frame!;
      expect(frame.exit!.a, frame.exit!.b, reason: 'nothing to link');
      expect(frame.inner.bounds.right, closeTo(call.tile.right, 1e-9));
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
      expect(frame.exit!.a, frame.exit!.b, reason: 'nothing to link');
      expect(checkLayout(layout), isEmpty);
    });

    test('copies drawn in place end at a bar too, and the call in them', () {
      final layout = copiesWithCall();
      _expectEndBar(layout, '1', ways: 1);
      _expectEndBar(layout.nodes['1']!.frame!.inner, '1', ways: 1);
      expect(checkLayout(layout), isEmpty);
    });
  });

  test('step 9 finds a frame whose body or links are off their places', () {
    final layout = releaseWithPublish();
    final call = layout.nodes['5']!;
    final frame = call.frame!;
    List<String> problemsWith(FrameBox moved) => checkLayout(
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
            tile: call.tile,
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
      problemsWith(
        FrameBox(
          inner: frame.inner,
          entry: lower(frame.entry!),
          exit: frame.exit,
        ),
      ),
      containsAll([
        '5: bar is not level with the start in the frame',
        '5: the link to the start is off its place',
      ]),
    );
    expect(
      problemsWith(
        FrameBox(
          inner: frame.inner,
          entry: frame.entry,
          exit: lower(frame.exit!),
        ),
      ),
      contains('5: the link from the end is off its place'),
    );
    expect(
      problemsWith(
        FrameBox(inner: layoutOf('release'), entry: null, exit: null),
      ),
      containsAll([
        '5: the body is not in the frame',
        '5: the body has several ends',
      ]),
    );
  });

  group('two levels nested', () {
    for (final (name, lay, outer, inner) in [
      ('a call in copies', copiesWithCall, '1', '1'),
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
      'bottom, its least width, the outlines over it', () {
    const room = FrameRoom(
      top: 70,
      side: 24,
      bottom: 30,
      width: 1200,
      above: 12,
    );
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
    expect(frame.exit!.a, frame.exit!.b, reason: 'nothing to link');
    expect(call.marks.top, call.tile.top - 12);
    expect(checkLayout(layout), isEmpty);
  });

  test('only calls and copies expand; ids the body does not have are left '
      'out', () {
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
    expect(call.frame!.exit, isNull);
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

  test('random bodies with random nodes expanded, nested, keep step 9 but '
      'for loops in capsules', () {
    for (var seed = 0; seed < 60; seed++) {
      final body = randomBody(seed);
      Map<String, ExpandedNode> expand(GraphBody body, int salt, int depth) => {
        for (final (i, node) in body.nodes.indexed)
          if ((node is CallNode || node is CopiesNode) &&
              (seed + salt + i) % 3 != 0 &&
              depth < 2)
            node.id: () {
              final inner = randomBody(seed * 31 + salt + i + 1);
              return ExpandedNode(
                inner,
                expanded: expand(inner, salt + i + 7, depth + 1),
              );
            }(),
      };
      final layout = layoutBody(body, expanded: expand(body, 0, 0));
      expect(
        checkLayout(layout).where((p) => !p.contains('loop crosses')),
        isEmpty,
        reason: 'seed $seed',
      );
      for (final node in layout.nodes.values) {
        final frame = node.frame;
        if (frame == null) continue;
        for (final edge in layout.edges) {
          if (edge.from == node.id || edge.to == node.id) continue;
          expect(
            _borderTouches(edge, node.tile),
            isEmpty,
            reason: 'seed $seed: ${edge.from}->${edge.to} at ${node.id}',
          );
        }
      }
    }
  });
}

/// Expects the end of the body in the frame of the node [id] of [layout] to
/// be a bar as a tile's input bar, the [ways] arrows that end the body
/// pointing at it: its width's middle on the frame's right side, its middle
/// level with the frame's exit, where the arrows out leave; the arrows at
/// their own heights a port gap apart round its middle, each an arrow gap
/// and a head before it; the bar past the outer ones as far as a tile's.
void _expectEndBar(GraphLayout layout, String id, {required int ways}) {
  final o = layout.options;
  final call = layout.nodes[id]!;
  final frame = call.frame!;
  final bar = frame.inner.nodes[endMarker]!.bar!;
  final rect = bar.rect;
  expect((rect.left + rect.right) / 2, closeTo(call.tile.right, 1e-9));
  expect(rect.width, closeTo(o.barWidth, 1e-9));
  final middle = (rect.top + rect.bottom) / 2;
  expect(middle, closeTo(frame.exit!.b.y, 1e-9));
  for (final out in layout.exits.where((x) => x.node == id)) {
    expect(out.anchor, Point(call.tile.right, middle));
  }
  final ends = frame.inner.edges.where((e) => e.to == endMarker).toList();
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
  // Half a port gap past the outer arrows, never shorter than the least
  // bar: as a tile's bar with as many inputs.
  expect(
    rect.height,
    closeTo(math.max(o.minBar, heights.last - heights.first + o.portGap), 1e-9),
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
