import 'package:nanoflow_ui/layout/layout.dart';
import 'package:test/test.dart';

import '../../tool/render_layout.dart' as render;
import '../layout/support.dart';

void main() {
  // Graphs with conditions and a call, and with copies.
  for (final (graph, function, kinds) in [
    ('release', 'release', {NodeKind.condition: 3, NodeKind.call: 1}),
    ('inline', 'inPlace', {NodeKind.copies: 1}),
  ]) {
    test('draws an effect as the terminal, a condition as the branch, a call '
        'and copies as ƒ, as the canvas does: $function of $graph', () {
      final layout = layoutOf(graph, function);
      final svg = render.renderSvg(layout, function);
      int drawn(String shape) => shape.allMatches(svg).length;
      int nodes(Set<NodeKind> of) =>
          layout.nodes.values.where((node) => of.contains(node.kind)).length;

      for (final MapEntry(key: kind, value: count) in kinds.entries) {
        expect(nodes({kind}), count, reason: '$kind');
      }
      // The terminal's prompt, the branch's link to its first node and the
      // hook of the ƒ: one of each per node of its kind.
      expect(drawn('M9 11l3.2 3L9 17'), nodes({NodeKind.effect}));
      expect(drawn('M9 14 h4'), nodes({NodeKind.condition}));
      expect(
        drawn('M5.5 22.5c1.6 0 2.4-1.1 2.8-3.1'),
        nodes({NodeKind.call, NodeKind.copies}),
      );
      // No diamond is left.
      expect(drawn('L23.5 14'), 0);
    });
  }
}
