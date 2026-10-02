import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart' hide Route;
import 'package:nanoflow_ui/graph/canvas/canvas_marks.dart';
import 'package:nanoflow_ui/layout/layout.dart';
import 'package:nanoflow_ui/state/session_view.dart';

import '../../state/support.dart';

void main() {
  final layout = layoutGraph(Graph.fromJson(reviewGraph));
  final mockup = Mockup();
  final marks = CanvasMarks.of(
    SessionView.of(
      mockup.session,
      now: Mockup.now,
      outcomes: mockup.outcomes,
      runId: 'e5f6-run',
      stepId: 'e5f6-notify-0',
    ),
  );

  EdgePath edge(String from, String to) =>
      layout.edges.firstWhere((e) => e.from == from && e.to == to);

  Iterable<EdgePath> into(String node) =>
      layout.edges.where((e) => e.to == node);

  test('the selected run\'s arrows, exits and bars are its path', () {
    expect(marks.edge(edge('collect', 'is-empty')), Tone.path);
    expect(marks.edge(edge('fix', 'inspect')), Tone.path);
    expect(marks.edge(edge('verdict', 'notify')), Tone.path);
    expect(marks.exit('verdict', 0), Tone.path);
    expect(marks.exit('is-empty', 1), Tone.path);
    expect(marks.bar('notify', into('notify')), Tone.path);
    expect(marks.bar('inspect', into('inspect')), Tone.path);
  });

  test('what other runs went along is taken; what none did, untaken', () {
    // c3d4 went to publish from the same capsule as e5f6 to notify.
    expect(marks.edge(edge('verdict', 'publish')), Tone.taken);
    expect(marks.bar('publish', into('publish')), Tone.taken);
    expect(marks.edge(edge('is-empty', 'discard')), Tone.untaken);
    expect(marks.exit('is-empty', 0), Tone.untaken);
    expect(marks.bar('discard', into('discard')), Tone.untaken);
  });

  test('counters, states, markers, visits and the ring', () {
    expect(marks.counter('inspect', 0), '2×');
    expect(marks.counter('verdict', 0), '1×');
    expect(marks.counter('is-empty', 0), isNull);
    expect(marks.state('notify'), NodeState.running);
    expect(marks.state('discard'), NodeState.notVisited);
    expect([for (final m in marks.markers('publish')) m.shortId], ['c3d4']);
    expect(marks.visits('verdict'), '2×');
    expect(marks.visits('fix'), isNull);
    expect(marks.selectedNode, 'notify');
    expect(marks.runId, 'e5f6');
  });

  test('Current graph is plain', () {
    const plain = CanvasMarks.plain;
    expect(CanvasMarks.of(null), same(plain));
    expect(plain.edge(edge('collect', 'is-empty')), Tone.plain);
    expect(plain.exit('collect', 0), Tone.plain);
    expect(plain.bar('inspect', into('inspect')), Tone.plain);
    expect(plain.counter('inspect', 0), isNull);
    expect(plain.state('collect'), isNull);
    expect(plain.markers('notify'), isEmpty);
    expect(plain.visits('inspect'), isNull);
    expect(plain.selectedNode, isNull);
  });
}
