// The app against the real engine, live (docs/ui-spec.md «Что это»: «Всё
// живое»). Needs macOS and the Dart SDK on PATH; not part of tool/ci.sh:
//
//   cd apps/nanoflow_ui
//   flutter test integration_test/live_test.dart -d macos
//
// It builds `nanoflow` from apps/nanoflow_cli, puts it on the PATH it gives
// the app next to tool/dev/fake-nanoflow-yaml as `nanoflow-yaml`, copies
// examples/review to a temporary directory as graph.dart with a graph.yaml
// beside it, opens graph.yaml and runs the graph there with `nanoflow run`.
// Screenshots of the window go to build/live_screenshots/.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nanoflow_ui/app.dart';
import 'package:nanoflow_ui/graph/canvas/node_tile.dart';
import 'package:nanoflow_ui/graph/details/step_details_window.dart';
import 'package:nanoflow_ui/graph/graph_screen.dart';
import 'package:nanoflow_ui/graph/logs/step_details_pane.dart';
import 'package:nanoflow_ui/graph/logs/step_list.dart';
import 'package:nanoflow_ui/graph/run_switcher.dart';
import 'package:nanoflow_ui/graph/sessions_column.dart';
import 'package:nanoflow_ui/platform/shell.dart';
import 'package:nanoflow_ui/start/recent_graphs.dart';
import 'package:nanoflow_ui/start/start_screen.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late final String repo;
  late final Directory temp;
  late final String bin;
  late final String dir;
  late final String yaml;
  late final String program;
  late final String path;

  setUpAll(() async {
    repo = _repositoryRoot();
    temp = await Directory.systemTemp.createTemp('nanoflow_live_');
    bin = p.join(temp.path, 'bin');
    await Directory(bin).create();
    final built = await Process.run('dart', [
      'compile',
      'exe',
      p.join(repo, 'apps/nanoflow_cli/bin/nanoflow.dart'),
      '-o',
      p.join(bin, 'nanoflow'),
    ], workingDirectory: repo);
    if (built.exitCode != 0) {
      fail('nanoflow did not build:\n${built.stdout}${built.stderr}');
    }
    await Link(p.join(bin, 'nanoflow-yaml'))
        .create(p.join(repo, 'tool/dev/fake-nanoflow-yaml'));
    path = '$bin:${Platform.environment['PATH']}';

    dir = p.join(temp.path, 'review');
    await Directory(dir).create();
    yaml = p.join(dir, 'graph.yaml');
    program = p.join(dir, 'graph.dart');
    await File(p.join(repo, 'examples/review/input.json'))
        .copy(p.join(dir, 'input.json'));
    // Only its name matters: the stand-in runs graph.dart beside it.
    await File(yaml).writeAsString('# stands for graph.dart\n');
    await File(program).writeAsString(
      _slowNotify(
        await File(p.join(repo, 'examples/review/graph.dart')).readAsString(),
      ),
    );
  });

  tearDownAll(() async {
    await temp.delete(recursive: true);
  });

  testWidgets('follows a session of the real engine live', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final recent = RecentGraphs(await SharedPreferences.getInstance());
    final shots = _Screenshots(tester);
    tester.view
      ..physicalSize = const Size(2880, 1800)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RepaintBoundary(
        key: _Screenshots.key,
        child: NanoflowApp(
          recent: recent,
          shell: Shell(
            environment: {...Platform.environment, 'PATH': path},
            terminal: true,
          ),
          pickFile: () async => yaml,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(StartScreen), findsOneWidget);
    await shots.take('01-start-empty');

    // Open graph: the current graph comes from nanoflow-yaml, checked.
    await tester.tap(find.text('Open graph'));
    await _until(tester, find.byKey(NodeTile.keyOf('collect')));
    expect(find.byType(GraphScreen), findsOneWidget);
    expect(find.text('Live · watching runs/'), findsOneWidget);
    expect(find.text('No runs yet'), findsOneWidget);
    expect(find.text('graph.yaml'), findsOneWidget);
    expect(find.text('2×'), findsNothing);
    await shots.take('02-current-graph-no-runs');

    // A session of the real engine appears and runs.
    final engine = await _Engine.start(bin: bin, dir: dir, path: path);
    addTearDown(engine.kill);
    final sessionId = await engine.sessionId;
    final card = find.byKey(SessionsColumn.cardKey(sessionId));
    await _until(tester, card);
    expect(
      find.descendant(of: card, matching: find.textContaining('Running for')),
      findsOneWidget,
    );
    // A session that starts after the graph is opened is not selected.
    expect(find.byType(RunSwitcher), findsNothing);
    await tester.tap(card);
    await tester.pump();

    // The run splits into publish and notify; notify waits, logging.
    await _until(tester, find.text('split'));
    // A scan may give run-split before it lists the runs the split made.
    await _until(tester, _runPills(), atLeast: 3);
    expect(_runPills(), findsNWidgets(3));
    await tester.tap(
      find.byKey(RunSwitcher.pillKey(_runStartedAt(dir, 'notify'))),
    );
    await _until(tester, find.textContaining('waiting for release'));
    expect(
      find.descendant(
        of: find.byKey(NodeTile.keyOf('inspect')),
        matching: find.text('2×'),
      ),
      findsOneWidget,
    );
    expect(find.text('following tail'), findsOneWidget);
    expect(find.textContaining('Running for'), findsOneWidget);
    // Logs has the run's steps, the inherited ones and its own.
    expect(find.textContaining('8 steps, 7 inherited from'), findsOneWidget);
    for (final row in [
      find.text('collect'),
      find.textContaining('isEmpty else → inspect'),
      find.text('fix'),
      find.text('notify'),
    ]) {
      expect(
        find.descendant(of: find.byType(StepList), matching: row),
        findsOneWidget,
        reason: '$row',
      );
    }
    final logged = _lastWait(tester);
    await _until(
      tester,
      find.textContaining(RegExp('waiting for release ${logged + 2}\$')),
    );
    await shots.take('03-running-split');

    // Released, notify finishes and the session with it.
    await File(p.join(dir, 'release')).create();
    await _until(
      tester,
      find.descendant(of: card, matching: find.textContaining('Finished in')),
    );
    expect(await engine.exitCode, 0);
    await _until(tester, find.textContaining('parseConfig: accepted'));
    expect(find.text('following tail'), findsNothing);
    await shots.take('04-finished-split');

    // Open shows the selected step in the step details window.
    await tester.tap(find.byKey(StepDetailsPane.openKey));
    await _until(tester, find.byType(StepDetailsWindow));
    expect(find.text('Back to canvas'), findsOneWidget);
    await shots.take('05-step-details-notify');
    await tester.tap(find.byKey(StepDetailsWindow.backKey));
    await tester.pump();
    expect(find.byType(StepDetailsWindow), findsNothing);

    // A double click on inspect: its last visit in the run that split.
    await tester.tap(find.text('split'));
    await tester.pump();
    await _doubleTap(tester, find.byKey(NodeTile.tileKeyOf('inspect')));
    await _until(tester, find.byType(StepDetailsWindow));
    expect(find.textContaining('of 2'), findsOneWidget);
    await shots.take('06-step-details-inspect');
    await tester.tap(find.byKey(StepDetailsWindow.closeKey));
    await tester.pump();

    // Current graph follows edits of graph.dart.
    await tester.tap(find.byKey(SessionsColumn.currentGraphKey));
    await tester.pump();
    expect(find.byKey(NodeTile.keyOf('archive')), findsNothing);
    await File(program)
        .writeAsString(_withArchive(await File(program).readAsString()));
    await _until(tester, find.byKey(NodeTile.keyOf('archive')));
    await shots.take('07-current-graph-edited');

    // A description check rejects: its errors, the last good graph stays.
    await File(program)
        .writeAsString(_withOrphan(await File(program).readAsString()));
    await _until(tester, find.text('nanoflow check found 1 error'));
    expect(find.textContaining('nodes.orphan: unreachable'), findsOneWidget);
    expect(find.byKey(NodeTile.keyOf('archive')), findsOneWidget);
    expect(find.byKey(NodeTile.keyOf('orphan')), findsNothing);
    await shots.take('08-check-errors');

    // The graph file is deleted while open: a banner, the graph stays.
    await File(yaml).delete();
    await _until(tester, find.text('File unavailable'));
    expect(find.text('File unavailable · watching runs/'), findsOneWidget);
    expect(find.byKey(NodeTile.keyOf('archive')), findsOneWidget);
    await shots.take('09-file-unavailable');

    // Back on the start screen the graph is missing.
    await tester.tap(find.text('Graphs'));
    await tester.pump();
    expect(find.text('Missing'), findsOneWidget);
    await shots.take('10-start-missing');
  });
}

/// The repository this app is in: the app's tests run from its directory.
String _repositoryRoot() {
  var dir = Directory.current.absolute;
  while (!File(p.join(dir.path, 'tool/dev/fake-nanoflow-yaml')).existsSync()) {
    if (dir.parent.path == dir.path) {
      fail(
        'run from apps/nanoflow_ui: no repository above ${Directory.current}',
      );
    }
    dir = dir.parent;
  }
  return dir.path;
}

/// [source], the review example, with a `notify` that logs a line every
/// 300 ms until a file `release` appears next to the program: its session
/// stays running for as long as the test looks at it.
String _slowNotify(String source) => _replace(
  _replace(source, "import 'dart:convert';", '''
import 'dart:convert';
import 'dart:io';
'''),
  '''
final notify = node((Report r) async {
  print('\${r.change.id}: accepted');
});''',
  '''
final notify = node((Report r) async {
  final release = File.fromUri(Platform.script.resolve('release'));
  for (var i = 1; !release.existsSync(); i++) {
    print('waiting for release \$i');
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  print('\${r.change.id}: accepted');
});''',
);

/// [source] with a node `archive` after an accepted verdict.
String _withArchive(String source) => _replace(
  _replace(
    source,
    'Verdict.accepted: {publish, notify},',
    'Verdict.accepted: {publish, notify, archive},',
  ),
  'final graph = Graph([',
  '''
final archive = node((Report r) async {});

final graph = Graph([''',
);

/// [source] with a node `orphan` no arrow leads to: the Dart library builds
/// the graph, `nanoflow check` finds the node unreachable.
String _withOrphan(String source) => _replace(
  _replace(source, 'final graph = Graph([', '''
final orphan = node((Report r) async => r);

final graph = Graph(['''),
  'Graph.part(fix).next(inspect),',
  '''
Graph.part(fix).next(inspect),
  Graph.part(orphan).next(publish),''',
);

String _replace(String source, String from, String to) {
  if (!source.contains(from)) fail('the review example has no `$from`');
  return source.replaceFirst(from, to);
}

/// `nanoflow run -- nanoflow-yaml graph.yaml < input.json` in [dir].
final class _Engine {
  _Engine._(this._process) {
    final lines = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_stderr.add);
    sessionId = lines.first;
  }

  static Future<_Engine> start({
    required String bin,
    required String dir,
    required String path,
  }) async {
    final process = await Process.start(
      p.join(bin, 'nanoflow'),
      ['run', '--', 'nanoflow-yaml', 'graph.yaml'],
      workingDirectory: dir,
      environment: {'PATH': path},
    );
    process.stdin.add(await File(p.join(dir, 'input.json')).readAsBytes());
    await process.stdin.close();
    return _Engine._(process);
  }

  final Process _process;
  final List<String> _stderr = [];

  /// What the engine printed on stdout: the session id.
  late final Future<String> sessionId;

  Future<int> get exitCode => _process.exitCode.timeout(
    const Duration(seconds: 30),
    onTimeout: () => fail('nanoflow run did not end:\n${_stderr.join('\n')}'),
  );

  void kill() => _process.kill();
}

/// Pumps until [finder] finds [atLeast] widgets, for at most [timeout].
Future<void> _until(
  WidgetTester tester,
  Finder finder, {
  int atLeast = 1,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().length < atLeast) {
    if (DateTime.now().isAfter(end)) fail('gave up waiting for $finder');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The number of the last `waiting for release N` line the log shows.
int _lastWait(WidgetTester tester) {
  var last = 0;
  for (final element in find.textContaining('waiting for release').evaluate()) {
    final text = (element.widget as Text).data!;
    last = math.max(last, int.parse(text.split(' ').last));
  }
  return last;
}

/// The id of the run of the session in [dir] that started at [node].
String _runStartedAt(String dir, String node) {
  for (final log
      in Directory(p.join(dir, 'runs'))
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => p.basename(file.path) == 'log.jsonl')) {
    final first =
        jsonDecode(log.readAsLinesSync().first) as Map<String, Object?>;
    if (first['node'] == node) return first['runId']! as String;
  }
  fail('no run started at $node');
}

/// The runs in the run switcher.
Finder _runPills() => find.descendant(
  of: find.byType(RunSwitcher),
  matching: find.byWidgetPredicate(
    (widget) => switch (widget.key) {
      ValueKey<(String, String)>(value: ('run', _)) => true,
      _ => false,
    },
  ),
);

/// Two taps on [finder] close enough to make a double click.
Future<void> _doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 400));
}

/// Pictures of the whole window, saved under build/live_screenshots/.
final class _Screenshots {
  _Screenshots(this.tester);

  final WidgetTester tester;

  static const key = ValueKey('live screenshots');

  static final directory = Directory('build/live_screenshots');

  Future<void> take(String name) async {
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File(p.join(directory.path, '$name.png'));
    await file.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
  }
}
