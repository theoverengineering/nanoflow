import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/layout/layout.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The bodies describe writes: the review example's workflow, and the
/// release and inline fixtures of `nanoflow_describe`.
void main() {
  for (final name in ['review', 'release', 'inline']) {
    group('every body of the $name graph', () {
      final file = loadGraphFile(name);
      for (final MapEntry(key: id, value: body) in bodiesOf(file).entries) {
        test('$id keeps every rule and crosses nothing', () {
          final layout = layoutBody(body, functions: file.functions);
          expect(checkLayout(layout), isEmpty);
          expect(countCrossings(layout), 0);
        });
      }
    });
  }

  /// The ids of the arrows of [layout] as `from-label->to`.
  List<String> arrows(GraphLayout layout) => [
    for (final edge in layout.edges)
      '${edge.from}-${exitOf(layout, edge.from, edge.exitIndex).label}'
          '->${edge.to}',
  ];

  group('review', () {
    late GraphLayout layout;
    setUpAll(() => layout = layoutOf('review'));

    test('starts at the start marker and ends at an end marker for each way '
        'out', () {
      expect(layout.nodes.keys, [
        startMarker,
        for (var i = 1; i <= 8; i++) '$i',
        endMarker,
        endMarkerAt(2),
        endMarkerAt(3),
      ]);
      final start = layout.nodes[startMarker]!;
      expect(start.kind, NodeKind.start);
      expect(start.inside, 'start');
      expect(start.layer, 0);
      expect(start.bar, isNull);
      final end = layout.nodes[endMarker]!;
      expect(end.kind, NodeKind.end);
      expect(end.inside, 'end');
      expect(end.bar!.inputs, hasLength(1));
      // Each right after the node it ends.
      expect(end.layer, layout.nodes['3']!.layer + 1);
      // Both markers are as wide as a tile, and lower.
      for (final marker in [start, end]) {
        expect(marker.tile.width, layout.options.tile);
        expect(marker.tile.height, lessThan(layout.options.tile));
        expect(marker.name, isNull);
        expect(marker.place, isNull);
      }
    });

    test('names steps and conditions, their places under them', () {
      final collect = layout.nodes['1']!;
      expect(collect.kind, NodeKind.step);
      expect(collect.name, 'collect');
      expect(collect.place, 'review.dart:49');
      expect(collect.inside, isNull);
      final empty = layout.nodes['2']!;
      expect(empty.kind, NodeKind.condition);
      expect(empty.name, 'change.path.isEmpty');
    });

    test('labels the edges out of conditions; side by side edges with one '
        'label leave one capsule', () {
      expect(arrows(layout), [
        '$startMarker-null->1',
        '1-null->2',
        '2-true->3',
        '2-false->4',
        '3-null->$endMarker',
        '4-null->5',
        '5-true->6',
        '5-true->7',
        '5-false->8',
        '6-null->${endMarkerAt(2)}',
        '7-null->${endMarkerAt(3)}',
        '8-null->4',
      ]);
      final split = exitOf(layout, '5', 0);
      expect(split.shape, ExitShape.capsule);
      expect(edgeOf(layout, '5', 0, 1).to, '7');
      expect(exitOf(layout, '5', 1).shape, ExitShape.dot);
      // fix goes back to inspect: dashed, round the bottom.
      expect(edgeOf(layout, '8', 0).kind, EdgeKind.back);
    });
  });

  group('release', () {
    test('draws a call as a stack named after the function, the steps of '
        'its body counted on it', () {
      final layout = layoutOf('release');
      final call = layout.nodes['5']!;
      expect(call.kind, NodeKind.call);
      expect(call.name, 'publish()');
      // upload, verify, rollback.
      expect(call.inside, '{ 3 }');
      expect(call.node, isA<CallNode>());
      expect(arrows(layout), [
        '$startMarker-null->1',
        '1-null->2',
        '2-each->3',
        '2-done->6',
        '3-null->4',
        '4-true->5',
        '4-false->2',
        '5-null->2',
        '6-Channel.stable->7',
        '6-Channel.beta->8',
        '6-Channel.dev->8',
        '7-null->$endMarker',
        '8-null->${endMarkerAt(2)}',
      ]);
      // A case of its own for each label, even into one node.
      expect(exitOf(layout, '6', 1).shape, ExitShape.dot);
      expect(exitOf(layout, '6', 2).shape, ExitShape.dot);
    });

    test('a condition may end the body', () {
      final layout = layoutOf('release', 'publish');
      expect(arrows(layout), [
        '$startMarker-null->1',
        '1-null->2',
        '2-null->3',
        '3-true->4',
        '3-false->$endMarker',
        '4-null->${endMarkerAt(2)}',
      ]);
    });
  });

  group('inline', () {
    test('draws copies as a stack labelled with what they go over, the '
        'steps of a copy counted on it', () {
      final layout = layoutOf('inline', 'inPlace');
      final copies = layout.nodes['1']!;
      expect(copies.kind, NodeKind.copies);
      expect(copies.name, 'pkg in packages');
      // upload, verify, tag.
      expect(copies.inside, '{ 3 }');
      expect(arrows(layout), [
        '$startMarker-null->1',
        '1-null->2',
        '2-null->$endMarker',
      ]);
    });

    test('a call in copies counts the steps of the function', () {
      final file = loadGraphFile('inline');
      final copies = functionOf(
        file,
        'viaCall',
      ).body.nodes.whereType<CopiesNode>().single;
      final layout = layoutBody(copies.body, functions: file.functions);
      expect(layout.nodes['1']!.name, 'publish()');
      expect(layout.nodes['1']!.inside, '{ 3 }');
    });
  });

  group('the steps counted on a call or copies', () {
    test('are those of the bodies below too: of the functions called and '
        'of copies', () {
      // viaCall's copies hold one call of publish: upload, verify, tag.
      expect(layoutOf('inline', 'viaCall').nodes['1']!.inside, '{ 3 }');
    });

    test('count a function being counted once: a recursive call adds '
        'nothing again', () {
      // crawl calls visit, which has no step of its own and calls crawl:
      // the fetch of crawl.
      final crawl = layoutOf('recursion', 'crawl');
      expect(crawl.nodes['3']!.name, 'visit()');
      expect(crawl.nodes['3']!.inside, '{ 1 }');
      // deploy calls itself: its try-deploy.
      expect(layoutOf('recursion', 'deploy').nodes['3']!.inside, '{ 1 }');
    });

    test('are left out when there are none below', () {
      const empty = GraphBody(nodes: [], edges: []);
      final layout = layoutBody(
        const GraphBody(
          nodes: [
            CallNode(id: 'call', place: null, functions: ['lib/a.dart#none']),
            CopiesNode(id: 'copies', place: null, label: 'x', body: empty),
          ],
          edges: [],
        ),
        functions: const {
          'lib/a.dart#none': GraphFunction(
            id: 'lib/a.dart#none',
            name: 'none',
            place: null,
            body: empty,
          ),
        },
      );
      expect(layout.nodes['call']!.inside, '{ }');
      expect(layout.nodes['copies']!.inside, '{ }');
    });
  });

  test('a name longer than 30 characters is cut with …, whole in '
      'fullName', () {
    const label = 'change.path.isEmpty && change.id.isNotEmpty';
    final layout = layoutBody(
      const GraphBody(
        nodes: [
          ConditionNode(id: 'long', place: null, label: label),
          StepNode(id: 'short', place: null, name: 'collect'),
        ],
        edges: [],
      ),
    );
    final long = layout.nodes['long']!;
    expect(long.name, 'change.path.isEmpty && change…');
    expect(long.name!.runes, hasLength(30));
    expect(long.fullName, label);
    expect(layout.nodes['short']!.name, 'collect');
    expect(layout.nodes['short']!.fullName, 'collect');
  });

  test('a call to a function the file does not have is named from its id', () {
    final layout = layoutBody(
      const GraphBody(
        nodes: [
          CallNode(id: '1', place: null, functions: ['lib/a.dart#Box.pack']),
        ],
        edges: [
          GraphEdge(from: null, to: '1', label: null),
          GraphEdge(from: '1', to: null, label: null),
        ],
      ),
    );
    expect(layout.nodes['1']!.name, 'pack()');
    expect(layout.nodes['1']!.inside, '{ ? }');
    expect(layout.nodes['1']!.place, isNull);
  });

  test('a call to implementations with as many steps or not', () {
    final file = loadGraphFile('interfaces');
    final layout = layoutOf('interfaces', 'deploy');
    final call = layout.nodes.values.firstWhere((n) => n.kind == NodeKind.call);
    expect(call.name, 'notify()');
    // ChatNotifier.notify has one step, MailNotifier.notify two.
    expect(
      [
        for (final id in (call.node! as CallNode).functions)
          file.functions[id]!.body.nodes.whereType<StepNode>().length,
      ],
      [1, 2],
    );
    expect(call.inside, '{ 1–2 }');
  });

  test('a body with no steps goes from the start marker to the end marker', () {
    final layout = layoutBody(
      const GraphBody(
        nodes: [],
        edges: [GraphEdge(from: null, to: null, label: null)],
      ),
    );
    expect(arrows(layout), ['$startMarker-null->$endMarker']);
    expect(checkLayout(layout), isEmpty);
  });

  test('a body side by side from its start leaves the start marker by one '
      'capsule', () {
    final layout = layoutBody(
      bodyOf({
        'start': ['a', 'b'],
        'nodes': {
          'a': {'command': 'a', 'then': <String>[]},
          'b': {'command': 'b', 'then': <String>[]},
        },
      }),
    );
    expect(exitOf(layout, startMarker, 0).shape, ExitShape.capsule);
    expect(checkLayout(layout), isEmpty);
  });
}
