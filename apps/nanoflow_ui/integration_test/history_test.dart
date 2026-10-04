// The app opening a graph file with a long history: 200 sessions of 30
// effects each, written as files the way the workflow library writes them.
// Needs macOS; not part of tool/ci.sh:
//
//   cd apps/nanoflow_ui
//   flutter test integration_test/history_test.dart -d macos
//
// Measures how long the newest session and the whole history take to show,
// and the longest frame while they load and after: they are in a failure's
// reason. The binding's reportData gets them too, but only `flutter drive`
// writes it out, not `flutter test`.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_ui/app.dart';
import 'package:nanoflow_ui/graph/session_bar.dart';
import 'package:nanoflow_ui/graph/sessions_column.dart';
import 'package:nanoflow_ui/platform/shell.dart';
import 'package:nanoflow_ui/start/recent_graphs.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// How many sessions the history has, and effects each.
const _sessions = 200;
const _effects = 30;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late final Directory temp;
  late final String graphFile;
  late final String newest;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('nanoflow_history_');
    graphFile = p.join(temp.path, graphFileName);
    _json(graphFile, _graph);
    newest = _writeHistory(runsDirOf(temp.path));
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
        shell: Shell(),
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

/// Writes [_sessions] sessions of review to [runsDir], a day apart up to
/// yesterday, each [_effects] effects — collect, then inspect and fix round
/// and round, then inspect, publish and notify — that finished; returns
/// the id of the newest session.
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
    Directory(p.join(sessionDir, effectsDirName)).createSync();
    _json(
      p.join(sessionDir, sessionFileName),
      Session(
        id: sessionId,
        workflow: 'review',
        graph: _graph,
        inputId: null,
      ).toJson(),
    );
    String document(Object? value) {
      final id = newId();
      _json(
        p.join(sessionDir, documentsDirName, documentFileName(id)),
        Document(id: id, sessionId: sessionId, value: value).toJson(),
      );
      return id;
    }

    final events = <Event>[
      SessionStarted(time: time, code: _graph['fingerprint']! as String),
    ];
    final names = [
      'collect',
      for (var loop = 0; loop < (_effects - 4) ~/ 2; loop++) ...[
        'inspect',
        'fix',
      ],
      'inspect',
      'publish',
      'notify',
    ];
    String? after;
    final counts = <String, int>{};
    for (final name in names) {
      final effectId = newId();
      final key = '$name#${counts[name] = (counts[name] ?? 0) + 1}@0';
      final effectDir = p.join(
        sessionDir,
        effectsDirName,
        effectDirName(time, name, effectId),
      );
      Directory(effectDir).createSync();
      File(p.join(effectDir, logFileName)).writeAsStringSync(
        [for (var line = 0; line < 20; line++) '$name: line $line\n'].join(),
      );
      events.add(EffectStarted(time: time, effectId: effectId));
      time = time.add(const Duration(seconds: 7));
      final output = document({
        'change': 'parseConfig',
        'findings': <String>[],
      });
      _json(
        p.join(effectDir, effectFileName),
        Effect(
          id: effectId,
          sessionId: sessionId,
          name: name,
          key: key,
          after: after,
          place: 'lib/review.dart:${_lines[name]}',
          outputId: output,
          log: logFileName,
        ).toJson(),
      );
      events.add(
        EffectFinished(time: time, effectId: effectId, outputId: output),
      );
      after = key;
    }
    events.add(SessionFinished(time: time, outputId: null));
    File(p.join(sessionDir, eventsFileName)).writeAsStringSync(
      events.map((event) => '${jsonEncode(event.toJson())}\n').join(),
    );
    time = time.add(const Duration(days: 1));
  }
  return sessionId;
}

void _json(String path, Object? json) => File(path)
    .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(json)}\n');

/// The line of each effect of [_graph].
const _lines = {
  'collect': 2,
  'inspect': 4,
  'fix': 6,
  'publish': 8,
  'notify': 9,
};

/// A graph file of review: collect, inspect and fix in a loop until
/// inspect finds nothing, then publish and notify side by side.
const _graph = <String, Object?>{
  'format': 2,
  'package': 'review_example',
  'fingerprint': 'sha256:history',
  'sources': {'lib/review.dart': 'sha256:history'},
  'builds': <String, String>{},
  'workflows': ['lib/review.dart#review'],
  'functions': {
    'lib/review.dart#review': {
      'name': 'review',
      'place': 'lib/review.dart:1',
      'body': {
        'nodes': [
          {
            'id': '1',
            'kind': 'effect',
            'name': 'collect',
            'place': 'lib/review.dart:2',
          },
          {
            'id': '2',
            'kind': 'effect',
            'name': 'inspect',
            'place': 'lib/review.dart:4',
          },
          {
            'id': '3',
            'kind': 'fork',
            'label': 'report.findings.isEmpty',
            'place': 'lib/review.dart:5',
          },
          {
            'id': '4',
            'kind': 'effect',
            'name': 'fix',
            'place': 'lib/review.dart:6',
          },
          {
            'id': '5',
            'kind': 'effect',
            'name': 'publish',
            'place': 'lib/review.dart:8',
          },
          {
            'id': '6',
            'kind': 'effect',
            'name': 'notify',
            'place': 'lib/review.dart:9',
          },
        ],
        'edges': [
          {'from': null, 'to': '1', 'label': null},
          {'from': '1', 'to': '2', 'label': null},
          {'from': '2', 'to': '3', 'label': null},
          {'from': '3', 'to': '5', 'label': 'true'},
          {'from': '3', 'to': '6', 'label': 'true'},
          {'from': '3', 'to': '4', 'label': 'false'},
          {'from': '4', 'to': '2', 'label': null},
          {'from': '5', 'to': null, 'label': null},
          {'from': '6', 'to': null, 'label': null},
        ],
      },
    },
  },
  'warnings': <Object?>[],
};
