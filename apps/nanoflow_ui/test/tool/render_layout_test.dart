import 'package:nanoflow_ui/layout/layout.dart';
import 'package:test/test.dart';

import '../../tool/render_layout.dart' as render;
import '../layout/support.dart';

void main() {
  test('draws an effect as the terminal, a condition as the branch and a '
      'call as ƒ, as the canvas does', () {
    final layout = layoutOf('release');
    final svg = render.renderSvg(layout, 'release');
    int drawn(String shape) => shape.allMatches(svg).length;
    int nodes(Set<NodeKind> kinds) =>
        layout.nodes.values.where((node) => kinds.contains(node.kind)).length;

    expect(nodes({NodeKind.condition}), 3);
    expect(nodes({NodeKind.call}), 1);
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
