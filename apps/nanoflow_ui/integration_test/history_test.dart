// The app opening a graph with a long history: 200 sessions of 30 steps
// each, written as files the way the engine writes them. Needs macOS; not
// part of tool/ci.sh:
//
//   cd apps/nanoflow_ui
//   flutter test integration_test/history_test.dart -d macos
//
// Measures how long the newest session and the whole history take to show,
// and the longest frame while they load and after: in the binding's
// reportData (written out by `flutter drive`) and in a failure's reason.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Step;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart' hide Route;
import 'package:nanoflow_ui/app.dart';
import 'package:nanoflow_ui/graph/session_bar.dart';
import 'package:nanoflow_ui/graph/sessions_column.dart';
import 'package:nanoflow_ui/platform/shell.dart';
import 'package:nanoflow_ui/start/recent_graphs.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// How many sessions the history has, and steps each.
const _sessions = 200;
const _steps = 30;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late final Directory temp;
  late final String graphFile;
  late final String newest;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('nanoflow_history_');
    graphFile = p.join(temp.path, 'review.yaml');
    await File(graphFile).writeAsString('');
    newest = _writeHistory(runsDirOf(graphFile));
  });

  tearDownAll(() => temp.delete(recursive: true));

  testWidgets('opens a graph with a long history at once and stays '
      'responsive', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view
      ..physicalSize = const Size(2880, 1800)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      NanoflowApp(
        recent: RecentGraphs(await SharedPreferences.getInstance()),
        // Without nanoflow-yaml: the sessions are what is looked at.
        shell: Shell(environment: const {'PATH': '/usr/bin:/bin'}),
        pickFile: () async => graphFile,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Open graph'));
    final opened = Stopwatch()..start();
    final newestShown = find.descendant(
      of: find.byType(SessionBar),
      matching: find.text(newest.substring(0, 4)),
    );
    final allShown = find.descendant(
      of: find.byType(SessionsColumn),
      matching: find.text('$_sessions'),
    );
    Duration? newestAt;
    final loading = <int>[];
    while (allShown.evaluate().isEmpty) {
      if (opened.elapsed > const Duration(minutes: 1)) {
        fail('the history did not load in a minute');
      }
      loading.add(await _frame(tester));
      if (newestAt == null && newestShown.evaluate().isNotEmpty) {
        newestAt = opened.elapsed;
      }
    }
    final allAt = opened.elapsed;
    final after = [for (var i = 0; i < 120; i++) await _frame(tester)];

    final measured = {
      'newestSessionMs': newestAt?.inMilliseconds,
      'allSessionsMs': allAt.inMilliseconds,
      'longestFrameLoadingMs': loading.reduce(math.max),
      'longestFrameAfterMs': after.reduce(math.max),
    };
    // What `flutter drive` writes out; a failure says it too.
    binding.reportData = {'history': measured};
    final reason = '$measured';
    expect(newestAt, lessThan(const Duration(seconds: 3)), reason: reason);
    expect(loading.reduce(math.max), lessThan(1000), reason: reason);
    expect(after.reduce(math.max), lessThan(500), reason: reason);
  });
}

/// How long, in milliseconds, a frame 16 ms from now takes to come.
Future<int> _frame(WidgetTester tester) async {
  final took = Stopwatch()..start();
  await tester.pump(const Duration(milliseconds: 16));
  return took.elapsedMilliseconds;
}

/// Writes [_sessions] sessions of the review graph to [runsDir], a day
/// apart up to yesterday, each a root run of [_steps] − 2 steps through the fix loop that
/// splits into publish and notify; returns the id of the newest session.
String _writeHistory(String runsDir) {
  var time = DateTime.now().toUtc().subtract(
    const Duration(days: _sessions + 1),
  );
  late String sessionId;
  for (var s = 0; s < _sessions; s++) {
    sessionId = newId();
    final sessionDir = p.join(
      runsDir,
      sessionDirName('review', time, sessionId),
    );
    Directory(p.join(sessionDir, documentsDirName)).createSync(recursive: true);
    _json(
      p.join(sessionDir, sessionFileName),
      Session(id: sessionId, graph: _graph).toJson(),
    );
    String document(Object? value) {
      final id = newId();
      _json(
        p.join(sessionDir, documentsDirName, documentFileName(id)),
        Document(id: id, sessionId: sessionId, value: value).toJson(),
      );
      return id;
    }

    /// A run of [nodes] that starts at [time] with [input] and ends with
    /// [last]; its directory.
    String run(
      String runId,
      String? parentId,
      List<String> nodes,
      String? input,
      Event Function(DateTime at) last,
    ) {
      final runDir = p.join(sessionDir, runDirName(time, runId));
      Directory(p.join(runDir, stepsDirName)).createSync(recursive: true);
      _json(
        p.join(runDir, runFileName),
        Run(id: runId, sessionId: sessionId, parentId: parentId).toJson(),
      );
      final events = <Event>[
        RunStarted(runId: runId, time: time, node: nodes.first),
      ];
      for (final (i, node) in nodes.indexed) {
        final stepId = newId();
        final stepDir = p.join(
          runDir,
          stepsDirName,
          stepDirName(time, node, stepId),
        );
        Directory(stepDir).createSync();
        File(p.join(stepDir, logFileName)).writeAsStringSync(
          [for (var line = 0; line < 20; line++) '$node: line $line\n'].join(),
        );
        events.add(
          StepStarted(runId: runId, time: time, stepId: stepId, node: node),
        );
        time = time.add(const Duration(seconds: 7));
        final output = switch (node) {
          'publish' || 'notify' => null,
          'isEmpty' => document(false),
          'verdict' => document(
            i == nodes.length - 1 ? 'accepted' : 'returned',
          ),
          _ => document({'change': 'parseConfig', 'findings': <String>[]}),
        };
        _json(
          p.join(stepDir, stepFileName),
          Step(
            id: stepId,
            runId: runId,
            inputId: i == 0 ? input : null,
            outputId: output,
            log: logFileName,
          ).toJson(),
        );
        events.add(
          StepFinished(
            runId: runId,
            time: time,
            stepId: stepId,
            exitCode: 0,
            outputId: output,
          ),
        );
      }
      events.add(last(time));
      File(p.join(runDir, eventsFileName)).writeAsStringSync(
        events.map((event) => '${jsonEncode(event.toJson())}\n').join(),
      );
      return runDir;
    }

    final rootId = newId();
    run(
      rootId,
      null,
      [
        'collect',
        'isEmpty',
        for (var loop = 0; loop < (_steps - 6) ~/ 3; loop++) ...[
          'inspect',
          'verdict',
          'fix',
        ],
        'inspect',
        'verdict',
      ],
      document({'branch': 'parseConfig'}),
      (at) => RunSplit(runId: rootId, time: at),
    );
    for (final node in ['publish', 'notify']) {
      final childId = newId();
      run(
        childId,
        rootId,
        [node],
        null,
        (at) => RunFinished(runId: childId, time: at),
      );
    }
    time = time.add(const Duration(days: 1));
  }
  return sessionId;
}

void _json(String path, Object? json) => File(path)
    .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(json)}\n');

/// The review graph of README «Формат».
const _graph = <String, Object?>{
  'start': 'collect',
  'nodes': {
    'collect': {'command': 'nodes/collect/run.sh', 'then': 'isEmpty'},
    'isEmpty': {
      'decide': 'nodes/is-empty/run.sh',
      'then': 'discard',
      'else': 'inspect',
    },
    'inspect': {'command': 'nodes/inspect/run.sh', 'then': 'verdict'},
    'verdict': {
      'decide': 'nodes/verdict/run.sh',
      'then': {
        'accepted': ['publish', 'notify'],
        'returned': 'fix',
      },
    },
    'fix': {'command': 'nodes/fix/run.sh', 'then': 'inspect'},
    'publish': {'command': 'nodes/publish/run.sh'},
    'notify': {'command': 'nodes/notify/run.sh'},
    'discard': {'command': 'nodes/discard/run.sh'},
  },
};
