import 'package:nanoflow_describe/nanoflow_describe.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The warnings about side effects outside effects (effects design §3) in
/// the fixture `test/fixtures/side_effects/`: a file per case, each with its
/// workflow.
void main() {
  late List<GraphWarning> warnings;

  setUpAll(() async {
    final result = await describePackage(
      p.join('test', 'fixtures', 'side_effects'),
      packageName: 'side_effects',
    );
    expect(result.errors, isEmpty);
    warnings = result.graph!.warnings;
  });

  /// The warnings about side effects at places in `lib/<file>`, in the order
  /// of the graph file, as `line: message`.
  List<String> sideEffectsIn(String file) => [
    for (final GraphWarning(:place, :message) in warnings)
      if (place!.startsWith('lib/$file:') &&
          message.startsWith('side effect outside an effect'))
        '${place.substring('lib/$file:'.length)}: $message',
  ];

  test('warns at every side effect the rule names in the body of a graph '
      'function, once for a chain of members', () {
    expect(sideEffectsIn('direct.dart'), [
      '11: side effect outside an effect: DateTime.now()',
      '12: side effect outside an effect: DateTime.timestamp()',
      '13: side effect outside an effect: Stopwatch()',
      '14: side effect outside an effect: Random()',
      '15: side effect outside an effect: Random(1)',
      '16: side effect outside an effect: Random.secure()',
      // The first of the chain: a member of what a side effect gives is one
      // too.
      "17: side effect outside an effect: File('x')",
      '18: side effect outside an effect: Directory.current',
      '19: side effect outside an effect: Platform.environment',
      "20: side effect outside an effect: Process.run('ls', [])",
      '21: side effect outside an effect: HttpClient()',
      "22: side effect outside an effect: Directory('x')",
      // Declared in dart:_internal, exported by dart:io.
      '23: side effect outside an effect: HttpStatus.ok',
      '24: side effect outside an effect: exitCode = 1',
      '26: side effect outside an effect: exit(0)',
      '33: side effect outside an effect: file.readAsStringSync()',
    ]);
  });

  test('warns at each call of a function, constructor, accessor or method of '
      'the package that reaches a side effect, and where a function is handed '
      'on, naming the first side effect it reaches, however deep', () {
    expect(sideEffectsIn('calls.dart'), [
      '11: side effect outside an effect: loadConfig() reaches '
          "File('config.json') at lib/config.dart:6",
      '17: side effect outside an effect: loadConfig() reaches '
          "File('config.json') at lib/config.dart:6",
      '21: side effect outside an effect: a() reaches DateTime.now() at '
          'lib/calls.dart:27',
      '30: side effect outside an effect: Settings() reaches DateTime.now() '
          'at lib/calls.dart:39',
      '31: side effect outside an effect: settings.home reaches '
          'Platform.environment at lib/calls.dart:43',
      '32: side effect outside an effect: settings.load() reaches '
          "File('config.json') at lib/config.dart:6",
      "33: side effect outside an effect: settings.home = '/' reaches "
          "File('home') at lib/calls.dart:45",
      // Not at 52, the call of the graph function direct: its side effects
      // warn in its own body.
      '58: side effect outside an effect: read reaches File(name) at '
          'lib/calls.dart:62',
    ]);
    // Not graph functions: their side effects warn where they are called.
    expect(sideEffectsIn('config.dart'), isEmpty);
  });

  test('does not warn about side effects in effects, nor in functions only '
      'effects call', () {
    expect(sideEffectsIn('inside.dart'), isEmpty);
  });

  test('lets logs, timers and Future.delayed be anywhere', () {
    expect(sideEffectsIn('logs.dart'), isEmpty);
  });

  test('walks a function that calls itself once', () {
    expect(sideEffectsIn('recursion.dart'), isEmpty);
  });
}
