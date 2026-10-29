import 'package:nanoflow_describe/nanoflow_describe.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The warnings about side effects outside effects (effects design §3) in
/// the routes of the fixture `test/fixtures/side_effects/`: a file per case,
/// each with its graphs.
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

  test('warns at every side effect the rule names in the body of a route, '
      'once for a chain of members', () {
    expect(sideEffectsIn('direct.dart'), [
      '16: side effect outside an effect: DateTime.now()',
      '17: side effect outside an effect: DateTime.timestamp()',
      '18: side effect outside an effect: Stopwatch()',
      '19: side effect outside an effect: Random()',
      '20: side effect outside an effect: Random(1)',
      '21: side effect outside an effect: Random.secure()',
      // The first of the chain: a member of what a side effect gives is one
      // too.
      "22: side effect outside an effect: File('x')",
      '23: side effect outside an effect: Directory.current',
      '24: side effect outside an effect: Platform.environment',
      "25: side effect outside an effect: Process.runSync('ls', [])",
      '26: side effect outside an effect: HttpClient()',
      "27: side effect outside an effect: Directory('x')",
      '28: side effect outside an effect: exitCode = 1',
      '29: side effect outside an effect: exit(0)',
      '38: side effect outside an effect: file.readAsStringSync()',
    ]);
  });

  test('lets constants, enum values, exceptions and their members of dart:io '
      'be anywhere, but not a static final value', () {
    expect(sideEffectsIn('values.dart'), [
      '15: side effect outside an effect: ContentType.json',
    ]);
  });

  test('warns where a constructor the rule names is torn off', () {
    expect(sideEffectsIn('tear_offs.dart'), [
      '11: side effect outside an effect: File.new',
      '12: side effect outside an effect: DateTime.now',
    ]);
  });

  test('warns at each call of a function, constructor, accessor or method of '
      'the package that reaches a side effect, and where a function is handed '
      'on, naming the first side effect it reaches, however deep', () {
    expect(sideEffectsIn('calls.dart'), [
      '14: side effect outside an effect: loadConfig() reaches '
          "File('config.json') at lib/config.dart:6",
      '22: side effect outside an effect: loadConfig() reaches '
          "File('config.json') at lib/config.dart:6",
      '29: side effect outside an effect: a() reaches DateTime.now() at '
          'lib/calls.dart:36',
      '40: side effect outside an effect: Settings() reaches DateTime.now() '
          'at lib/calls.dart:50',
      '41: side effect outside an effect: settings.home reaches '
          'Platform.environment at lib/calls.dart:54',
      '42: side effect outside an effect: settings.load() reaches '
          "File('config.json') at lib/config.dart:6",
      "43: side effect outside an effect: settings.home = '/' reaches "
          "File('home') at lib/calls.dart:56",
      // Not at 64, the call of the route touchAll: its side effects warn in
      // its own body.
      '75: side effect outside an effect: read reaches File(name) at '
          'lib/calls.dart:80',
    ]);
    // Not routes: their side effects warn where they are called.
    expect(sideEffectsIn('config.dart'), isEmpty);
  });

  test('does not warn about side effects in nodes, nor in functions only '
      'nodes call', () {
    expect(sideEffectsIn('inside.dart'), isEmpty);
  });

  test('lets logs, timers and Future.delayed be anywhere', () {
    expect(sideEffectsIn('logs.dart'), isEmpty);
  });

  test('walks functions that call themselves or each other, and gives all '
      'the functions of a ring the first side effect a walk from the first of '
      'them meets', () {
    expect(sideEffectsIn('recursion.dart'), [
      '20: side effect outside an effect: ping(n) reaches DateTime.now() at '
          'lib/recursion.dart:35',
      '27: side effect outside an effect: pong(n) reaches DateTime.now() at '
          'lib/recursion.dart:35',
      // rock → paper → scissors → rock: paper's time stamp comes first.
      '45: side effect outside an effect: rock(n) reaches '
          'DateTime.timestamp() at lib/recursion.dart:60',
      '46: side effect outside an effect: scissors(n) reaches '
          'DateTime.timestamp() at lib/recursion.dart:60',
      // middle reaches inner's time before its own time stamp.
      '70: side effect outside an effect: outer(n) reaches DateTime.now() at '
          'lib/recursion.dart:85',
    ]);
  });
}
