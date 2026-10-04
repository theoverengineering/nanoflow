import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/state/body_path.dart';
import 'package:test/test.dart';

import '../layout/support.dart';

void main() {
  final release = loadGraphFile('release');
  final releaseFunction = functionOf(release, 'release');
  final inline = loadGraphFile('inline');
  final interfaces = loadGraphFile('interfaces');

  List<String> titles(List<BodyLevel> levels) => [
    for (final level in levels) level.title,
  ];

  test('the workflow\'s body is the first level, its crumb the workflow\'s '
      'name', () {
    final levels = bodyLevels(releaseFunction, release.functions, const []);
    expect(titles(levels), ['release']);
    expect(levels.single.body, releaseFunction.body);
    expect(levels.single.opened, isNull);
  });

  test('a call opens the body of its function, its crumb the function '
      'with ()', () {
    final levels = bodyLevels(releaseFunction, release.functions, const [
      Opened('5', functionId: 'lib/publish.dart#publish'),
    ]);
    expect(titles(levels), ['release', 'publish()']);
    expect(
      levels.last.body,
      release.functions['lib/publish.dart#publish']!.body,
    );
    expect(
      levels.last.opened,
      const Opened('5', functionId: 'lib/publish.dart#publish'),
    );
  });

  test('copies open their body, their crumb their label; a call inside '
      'opens further', () {
    final viaCall = functionOf(inline, 'viaCall');
    final levels = bodyLevels(viaCall, inline.functions, const [
      Opened('1'),
      Opened('1', functionId: 'lib/inline.dart#publish'),
    ]);
    expect(titles(levels), ['viaCall', 'pkg in packages', 'publish()']);
    expect(levels[1].body, (viaCall.body.node('1')! as CopiesNode).body);
    expect(levels[2].body, inline.functions['lib/inline.dart#publish']!.body);
  });

  test('a path goes as deep as the graph has what it opens', () {
    List<String> deepest(List<Opened> path) =>
        titles(bodyLevels(releaseFunction, release.functions, path));

    // No such node; an effect; a function the call does not go to; a function
    // the file does not have; copies opened as a call.
    expect(deepest(const [Opened('9')]), ['release']);
    expect(deepest(const [Opened('3')]), ['release']);
    expect(
      deepest(const [Opened('5', functionId: 'lib/release.dart#release')]),
      ['release'],
    );
    final missing = {...release.functions}..remove('lib/publish.dart#publish');
    expect(
      titles(
        bodyLevels(releaseFunction, missing, const [
          Opened('5', functionId: 'lib/publish.dart#publish'),
        ]),
      ),
      ['release'],
    );
    expect(
      titles(
        bodyLevels(functionOf(inline, 'inPlace'), inline.functions, const [
          Opened('1', functionId: 'lib/inline.dart#publish'),
        ]),
      ),
      ['inPlace'],
    );
    // What follows an effect that does not open is left out too.
    expect(
      deepest(const [
        Opened('3'),
        Opened('5', functionId: 'lib/publish.dart#publish'),
      ]),
      ['release'],
    );
  });

  group('what a node opens', () {
    test('a call: each of its functions the file has, in its order', () {
      final deploy = functionOf(interfaces, 'deploy');
      final call = deploy.body.nodes.whereType<CallNode>().single;
      expect(openings(call, interfaces.functions), [
        Opened(call.id, functionId: 'lib/deploy.dart#ChatNotifier.notify'),
        Opened(call.id, functionId: 'lib/deploy.dart#MailNotifier.notify'),
      ]);
      expect(openings(call, const {}), isEmpty);
    });

    test('copies: their body; an effect or a condition: nothing', () {
      final inPlace = functionOf(inline, 'inPlace');
      expect(openings(inPlace.body.node('1')!, inline.functions), [
        const Opened('1'),
      ]);
      expect(openings(inPlace.body.node('2')!, inline.functions), isEmpty);
      expect(openings(releaseFunction.body.node('2')!, const {}), isEmpty);
    });

    test('a function is titled by what follows # in its id, with ()', () {
      expect(functionTitle('lib/publish.dart#publish'), 'publish()');
      expect(
        functionTitle('lib/deploy.dart#MailNotifier.notify'),
        'MailNotifier.notify()',
      );
    });
  });
}
