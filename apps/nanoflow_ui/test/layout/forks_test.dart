import 'dart:math';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/layout/layout.dart';
import 'package:test/test.dart';

import 'support.dart';

/// A random body of up to 12 effects and forks of `true` and `false`; a
/// fork lists either first, as describe does: `if` lists `true` first,
/// `a || b`, or an `if` that returns from a `try` with `finally`, `false`.
GraphBody randomForks(int seed) {
  final random = Random(seed);
  final count = 2 + random.nextInt(11);
  final ids = [for (var i = 0; i < count; i++) 'n$i'];
  String? target() =>
      random.nextInt(10) == 0 ? null : ids[random.nextInt(count)];
  final nodes = <GraphNode>[];
  final edges = [GraphEdge(from: null, to: ids.first, label: null)];
  for (final id in ids) {
    final place = 'lib/random.dart:${nodes.length + 1}';
    if (random.nextInt(3) == 0) {
      nodes.add(ConditionNode(id: id, place: place, label: 'decide $id'));
      final labels = random.nextBool() ? ['true', 'false'] : ['false', 'true'];
      for (final label in labels) {
        edges.add(GraphEdge(from: id, to: target(), label: label));
      }
    } else {
      nodes.add(EffectNode(id: id, place: place, name: 'run $id'));
      if (random.nextInt(6) > 0) {
        edges.add(GraphEdge(from: id, to: target(), label: null));
      }
    }
  }
  return GraphBody(nodes: nodes, edges: edges);
}

/// [lay] with every fork left where the order chosen for crossings and
/// arrows' length puts it: no fork turned with its `true` up.
GraphLayout _withoutTurningUp(GraphLayout Function() lay) {
  trueAboveEnabled = false;
  try {
    return lay();
  } finally {
    trueAboveEnabled = true;
  }
}

/// How many arrows going forward of [layout] turn three times or more.
int _thrice(GraphLayout layout) => layout.edges
    .where((e) => e.kind == EdgeKind.forward && turnsOf(e).length > 2)
    .length;

void main() {
  test('!ok in publish: its true goes up to rollback, though the end its '
      'false goes to would stand nearer over rollback than under it', () {
    GraphLayout lay() => layoutOf('release', 'publish');
    expect(falseAbove(_withoutTurningUp(lay)), ['3']);
    final layout = lay();
    expect(falseAbove(layout), isEmpty);
    expect(checkLayout(layout), isEmpty);
    expect(countCrossings(layout), 0);
  });

  for (final (graph, function) in [
    ('control', 'deployLocked'),
    ('throws', 'cleanUp'),
    ('throws', 'mirror'),
  ]) {
    test('$function of $graph: an if in a try with finally, whose false '
        'describe lists first, stands with its true up', () {
      expect(falseAbove(layoutOf(graph, function)), isEmpty);
    });
  }

  test('of the 268 forks of true and false in the test graphs at most 48 '
      'keep false above: their true goes back, turning it up would cost, or '
      'no swap of neighbours turns it up', () {
    var forks = 0;
    var above = 0;
    for (final name in graphNames()) {
      final file = loadGraphFile(name);
      for (final body in bodiesOf(file).values) {
        final layout = layoutBody(body, functions: file.functions);
        forks += layout.nodes.keys.where((id) {
          final labels = {
            for (final exit in layout.exits)
              if (exit.node == id) exit.label,
          };
          return labels.length == 2 && labels.containsAll(['true', 'false']);
        }).length;
        above += falseAbove(layout).length;
      }
    }
    expect(forks, 268);
    expect(above, lessThanOrEqualTo(48));
  });

  group('a fork turned with its true up costs no crossing, no rule of step '
      '9, no arrow turning twice or three times; at most a turn or half a '
      'tile of height for each fork turned up and each turn it saves', () {
    void check(GraphLayout Function() lay, String reason) {
      final layout = lay();
      final before = _withoutTurningUp(lay);
      final up = falseAbove(before).length - falseAbove(layout).length;
      if (falseAbove(layout).length == falseAbove(before).length) {
        expect(describe(layout), describe(before), reason: reason);
        return;
      }
      expect(up, greaterThan(0), reason: reason);
      expect(checkLayout(layout), isEmpty, reason: reason);
      expect(
        countCrossings(layout),
        lessThanOrEqualTo(countCrossings(before)),
        reason: reason,
      );
      final now = deepTurns(layout);
      final was = deepTurns(before);
      expect(now.turns, lessThanOrEqualTo(was.turns + up), reason: reason);
      expect(now.twice, lessThanOrEqualTo(was.twice), reason: reason);
      expect(
        _thrice(layout),
        lessThanOrEqualTo(_thrice(before)),
        reason: reason,
      );
      final saved = up + was.turns - now.turns + 2 * (was.twice - now.twice);
      expect(
        layout.bounds.height - before.bounds.height,
        lessThanOrEqualTo(layout.options.tile / 2 * saved + 1e-6),
        reason: reason,
      );
    }

    test('in the test graphs', () {
      for (final name in graphNames()) {
        final file = loadGraphFile(name);
        for (final MapEntry(key: id, value: body) in bodiesOf(file).entries) {
          check(() => layoutBody(body, functions: file.functions), '$name $id');
        }
      }
    });

    test('in random bodies', () {
      for (var seed = 0; seed < 300; seed++) {
        check(() => layoutBody(randomForks(seed)), 'seed $seed');
      }
    });
  });

  test('a random body with forks lays out the same way every time, keeping '
      'step 9', () {
    for (var seed = 0; seed < 300; seed++) {
      final layout = layoutBody(randomForks(seed));
      expect(
        describe(layoutBody(randomForks(seed))),
        describe(layout),
        reason: 'seed $seed',
      );
      expect(checkLayout(layout), isEmpty, reason: 'seed $seed');
    }
  });
}
