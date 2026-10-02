import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_reader/nanoflow_reader.dart';
import 'package:nanoflow_ui/state/step_files.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late String runsDir;
  final sessionId = newId();
  final runId = newId();
  final stepId = newId();
  final documentId = newId();
  final time = DateTime.utc(2026, 9, 21, 14, 3, 11);
  late String sessionDir;
  late String stepDir;

  void writeJson(String path, Object? json) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(json)}'
        '\n',
      );
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('step_files_test');
    runsDir = p.join(root.path, runsDirName);
    sessionDir = p.join(runsDir, sessionDirName('review', time, sessionId));
    writeJson(
      p.join(sessionDir, sessionFileName),
      Session(id: sessionId, graph: const {}).toJson(),
    );
    writeJson(
      p.join(sessionDir, documentsDirName, documentFileName(documentId)),
      Document(
        id: documentId,
        sessionId: sessionId,
        value: const {'branch': 'main'},
      ).toJson(),
    );
    final runDir = p.join(sessionDir, runDirName(time, runId));
    writeJson(
      p.join(runDir, runFileName),
      Run(id: runId, sessionId: sessionId, parentId: null).toJson(),
    );
    File(p.join(runDir, eventsFileName)).writeAsStringSync(
      '${jsonEncode(RunStarted(runId: runId, time: time, node: 'collect').toJson())}\n',
    );
    stepDir = p.join(
      runDir,
      stepsDirName,
      stepDirName(time, 'collect', stepId),
    );
    writeJson(
      p.join(stepDir, stepFileName),
      Step(
        id: stepId,
        runId: runId,
        inputId: documentId,
        outputId: null,
        log: logFileName,
      ).toJson(),
    );
    File(p.join(stepDir, logFileName)).writeAsStringSync('collecting\n');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('reads a step\'s log and documents, and tells their files once the '
      'feed has given them', () async {
    final reader = FsReader(runsDir: runsDir, graphName: 'review');
    final StepFiles files = ReaderFiles(reader);

    expect(await files.documentValue(sessionId, documentId), {
      'branch': 'main',
    });
    expect(await files.stepLog(sessionId, runId, stepId).first, 'collecting\n');
    expect(files.logPath(stepId), isNull);
    expect(files.stepPath(stepId), isNull);

    final changes = reader.changes().listen(null);
    addTearDown(changes.cancel);
    // The feed gives a session's documents after its runs.
    bool given() =>
        files.logPath(stepId) != null &&
        files.documentPath(sessionId, documentId) != null;
    for (var i = 0; i < 100 && !given(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(files.logPath(stepId), p.join(stepDir, logFileName));
    expect(files.stepPath(stepId), stepDir);
    expect(
      files.documentPath(sessionId, documentId),
      p.join(sessionDir, documentsDirName, documentFileName(documentId)),
    );
  });
}
