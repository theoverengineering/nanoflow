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

  test('a call in a function opened opens further', () {
    final viaCall = functionOf(inline, 'viaCall');
    final levels = bodyLevels(viaCall, inline.functions, const [
      Opened('1', functionId: 'lib/inline.dart#publishEach'),
      Opened('1', functionId: 'lib/inline.dart#publish'),
    ]);
    expect(titles(levels), ['viaCall', 'publishEach()', 'publish()']);
    expect(
      levels[1].body,
      inline.functions['lib/inline.dart#publishEach']!.body,
    );
    expect(levels[2].body, inline.functions['lib/inline.dart#publish']!.body);
  });

  test('a level has the doc of its function: the workflow\'s, a called '
      'one\'s; none without one', () {
    GraphFunction withDoc(GraphFunction f, String doc) => GraphFunction(
      id: f.id,
      name: f.name,
      place: f.place,
      doc: doc,
      body: f.body,
    );
    final viaCall = withDoc(functionOf(inline, 'viaCall'), 'Goes via a call.');
    const publish = 'lib/inline.dart#publish';
    final functions = {
      ...inline.functions,
      publish: withDoc(inline.functions[publish]!, 'Publishes [pkg].'),
    };
    final levels = bodyLevels(viaCall, functions, const [
      Opened('1', functionId: 'lib/inline.dart#publishEach'),
      Opened('1', functionId: publish),
    ]);
    expect(
      [for (final level in levels) level.doc],
      ['Goes via a call.', null, 'Publishes [pkg].'],
    );
    expect(
      bodyLevels(releaseFunction, release.functions, const []).single.doc,
      isNull,
    );
  });

  test('a path goes as deep as the graph has what it opens', () {
    List<String> deepest(List<Opened> path) =>
        titles(bodyLevels(releaseFunction, release.functions, path));

    // No such node; an effect; a function the call does not go to; a function
    // the file does not have.
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

    test('an effect or a condition: nothing', () {
      final viaCall = functionOf(inline, 'viaCall');
      expect(openings(viaCall.body.node('2')!, inline.functions), isEmpty);
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
