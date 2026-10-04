import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/copies.dart';
import 'package:nanoflow_ui/state/effect_places.dart';
import 'package:nanoflow_ui/state/graph_marks.dart';

import 'support.dart';

void main() {
  final file = copiesGraphFile();
  GraphFunction workflow(String name) =>
      file.functions['lib/copies.dart#$name']!;
  EffectPlaces placesOf(String name) =>
      EffectPlaces.of(workflow(name), file.functions);

  /// `inPlace` over core and tool: plan, then copies; core's tag runs,
  /// tool's verify failed.
  Journal inPlace() {
    final j = Journal('a1b2-session', workflow: 'inPlace')
      ..effect('plan', 1, end: 2, place: copiesAt(4), key: 'p', after: null);
    for (final (i, pkg) in ['core', 'tool'].indexed) {
      j.effect(
        'upload',
        3 + i,
        end: 5,
        place: copiesAt(7),
        key: 'u$pkg',
        after: 'p',
      );
    }
    j
      ..effect(
        'verify',
        6,
        end: 7,
        place: copiesAt(8),
        key: 'vcore',
        after: 'ucore',
      )
      ..effect(
        'verify',
        6,
        end: 8,
        failed: true,
        place: copiesAt(8),
        key: 'vtool',
        after: 'utool',
      )
      ..effect('tag', 9, place: copiesAt(9), key: 'tcore', after: 'vcore');
    return j;
  }

  test('two effects called on one line mark each its own node; an effect whose '
      'name is an expression marks every node of its line', () {
    // `await Future.wait([f.effect('lint', …), f.effect('test', …)]);` as
    // `dart format` leaves it, then two effects named by expressions.
    final check = GraphFunction(
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
    final session =
        (Journal('c1d2-session', workflow: 'check')
              ..effect('lint', 1, end: 2, place: 'lib/ci.dart:2')
              ..effect('test', 1, end: 3, failed: true, place: 'lib/ci.dart:2')
              ..effect('deploy-prod', 4, end: 5, place: 'lib/ci.dart:3'))
            .data;
    final marks = GraphMarks.of(
      check.body,
      places: EffectPlaces.of(check, {check.id: check}),
      session: session,
    );

    expect(marks.of('1')!.state, NodeState.visited);
    expect(marks.of('1')!.effects, 1);
    expect(marks.of('2')!.state, NodeState.failed);
    expect(marks.of('2')!.effects, 1);
    for (final id in ['3', '4']) {
      expect(marks.of(id)!.state, NodeState.visited, reason: id);
      expect(marks.of(id)!.effects, 1, reason: id);
    }
  });

  group('marks of the workflow body', () {
    final session = inPlace().data;
    final marks = GraphMarks.of(
      workflow('inPlace').body,
      places: placesOf('inPlace'),
      session: session,
    );

    test('an effect node with finished effects is visited', () {
      expect(marks.of('1')!.state, NodeState.visited);
      expect(marks.of('1')!.effects, 1);
    });

    test('a node without effects is not visited', () {
      expect(marks.of('3')!.state, NodeState.notVisited);
      expect(marks.of('3')!.effects, 0);
    });

    test('copies hold the effects of their copies: failed when one failed, '
        'whatever else runs; their count of copies', () {
      final copies = marks.of('2')!;
      expect(copies.state, NodeState.failed);
      expect(copies.effects, 5);
      expect(copies.running, 1);
      expect(copies.copies, 2);
    });

    test('an effect node has no count of copies', () {
      expect(marks.of('1')!.copies, isNull);
    });

    test('markers and unknown nodes have no marks', () {
      expect(marks.of('(start)'), isNull);
      expect(marks.of('nope'), isNull);
    });
  });

  group('marks of the body of the copies', () {
    final session = inPlace().data;
    final places = placesOf('inPlace');
    final frame = workflow('inPlace').body.node('2')! as CopiesNode;

    test('all copies: each node counts the effects of every copy on it, and '
        'how many run', () {
      final marks = GraphMarks.of(frame.body, places: places, session: session);
      expect(marks.of('1')!.effects, 2);
      expect(marks.of('2')!.state, NodeState.failed);
      expect(marks.of('3')!.state, NodeState.running);
      expect(marks.of('3')!.running, 1);
    });

    test('one copy: only its effects, the effects it has not reached not '
        'visited', () {
      final tool = copiesOf(frame, places: places, session: session)[1];
      final marks = GraphMarks.of(
        frame.body,
        places: places,
        session: session,
        effects: tool.effects,
      );
      expect(marks.of('1')!.state, NodeState.visited);
      expect(marks.of('1')!.effects, 1);
      expect(marks.of('2')!.state, NodeState.failed);
      expect(marks.of('3')!.state, NodeState.notVisited);
    });
  });

  test('a running effect outweighs finished ones on its node', () {
    final j = Journal('a1b2-session', workflow: 'inPlace')
      ..effect('plan', 1, end: 2, place: copiesAt(4))
      ..effect('plan', 3, place: copiesAt(4));
    final marks = GraphMarks.of(
      workflow('inPlace').body,
      places: placesOf('inPlace'),
      session: j.data,
    );
    expect(marks.of('1')!.state, NodeState.running);
    expect(marks.of('1')!.effects, 2);
    expect(marks.of('1')!.visitsText, '2×');
  });

  group('in a session whose process is gone (owner spec §6)', () {
    test('an effect that was running is interrupted: it outweighs finished '
        'ones on its node, and does not run', () {
      final j = Journal('a1b2-session', workflow: 'inPlace')
        ..effect('plan', 1, end: 2, place: copiesAt(4))
        ..effect('plan', 3, place: copiesAt(4))
        ..processGone();
      final marks = GraphMarks.of(
        workflow('inPlace').body,
        places: placesOf('inPlace'),
        session: j.data,
      );
      expect(marks.of('1')!.state, NodeState.interrupted);
      expect(marks.of('1')!.running, 0);
      expect(marks.of('1')!.effects, 2);
    });

    test('a failed effect outweighs it', () {
      final j = inPlace()..processGone();
      final frame = workflow('inPlace').body.node('2')! as CopiesNode;
      final places = placesOf('inPlace');
      final all = GraphMarks.of(frame.body, places: places, session: j.data);
      expect(all.of('3')!.state, NodeState.interrupted);
      expect(all.of('3')!.running, 0);
      final copies = GraphMarks.of(
        workflow('inPlace').body,
        places: places,
        session: j.data,
      ).of('2')!;
      expect(copies.state, NodeState.failed);
      expect(copies.running, 0);
    });

    test('runs as before while the process runs or is not known to', () {
      for (final alive in [true, null]) {
        final j = Journal('a1b2-session', workflow: 'inPlace')
          ..effect('plan', 3, place: copiesAt(4))
          ..owned(testOwner, alive: alive);
        final marks = GraphMarks.of(
          workflow('inPlace').body,
          places: placesOf('inPlace'),
          session: j.data,
        );
        expect(marks.of('1')!.state, NodeState.running);
        expect(marks.of('1')!.running, 1);
      }
    });
  });

  test('a call holds the effects of its functions', () {
    final j = Journal('e5f6-session', workflow: 'viaCall')
      ..effect('upload', 1, end: 2, place: copiesAt(20), key: 'u', after: null)
      ..effect('verify', 3, place: copiesAt(21), key: 'v', after: 'u');
    final copies = workflow('viaCall').body.node('1')! as CopiesNode;
    final marks = GraphMarks.of(
      copies.body,
      places: placesOf('viaCall'),
      session: j.data,
    );
    expect(marks.of('1')!.state, NodeState.running);
    expect(marks.of('1')!.effects, 2);
    expect(marks.of('1')!.copies, isNull);
  });

  test('an effect is on every node at its place (D13): a finally drawn on each '
      'way out of its try', () {
    const body = GraphBody(
      nodes: [
        ConditionNode(id: '1', place: 'lib/f.dart:2', label: 'ok'),
        EffectNode(id: '2', place: 'lib/f.dart:5', name: 'cleanup'),
        EffectNode(id: '3', place: 'lib/f.dart:5', name: 'cleanup'),
      ],
      edges: [],
    );
    const function = GraphFunction(
      id: 'lib/f.dart#f',
      name: 'f',
      place: 'lib/f.dart:1',
      body: body,
    );
    final j = Journal('a1b2-session', workflow: 'f')
      ..effect('cleanup', 1, end: 2, place: '/home/me/f/lib/f.dart:5');
    final marks = GraphMarks.of(
      body,
      places: EffectPlaces.of(function, {function.id: function}),
      session: j.data,
      selectedEffectId: j.effects.single.id,
    );
    expect(marks.of('2')!.state, NodeState.visited);
    expect(marks.of('3')!.state, NodeState.visited);
    expect(marks.of('1'), isNull, reason: 'a condition runs no effect');
    expect(marks.selected, {'2', '3'});
    expect(marks.nodesOf(j.effects.single.id), ['2', '3']);
  });

  test('the selected effect marks the node it is on, or the call or copies it '
      'is in', () {
    final j = inPlace();
    final tag = j.effects.last.id;
    final plan = j.effects.first.id;
    final body = workflow('inPlace').body;
    GraphMarks marksOf(String effectId) => GraphMarks.of(
      body,
      places: placesOf('inPlace'),
      session: j.data,
      selectedEffectId: effectId,
    );
    expect(marksOf(tag).selected, {'2'});
    expect(marksOf(plan).selected, {'1'});
    expect(marksOf(plan).nodesOf(tag), ['2']);
  });

  test('an effect at no node of the body is on none of it', () {
    final j = Journal('a1b2-session', workflow: 'inPlace')
      ..effect('stray', 1, end: 2, place: 'lib/old.dart:3');
    final marks = GraphMarks.of(
      workflow('inPlace').body,
      places: placesOf('inPlace'),
      session: j.data,
      selectedEffectId: j.effects.single.id,
    );
    expect(marks.selected, isEmpty);
    expect(marks.nodesOf(j.effects.single.id), isEmpty);
    expect(marks.of('1')!.state, NodeState.notVisited);
  });
}
