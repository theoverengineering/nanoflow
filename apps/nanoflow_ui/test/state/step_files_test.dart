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
    runsDir = runsDirOf(root.path);
    sessionDir = p.join(runsDir, sessionDirName('review', time, sessionId));
    writeJson(
      p.join(sessionDir, sessionFileName),
      Session(
        id: sessionId,
        workflow: 'review',
        graph: null,
        inputId: null,
      ).toJson(),
    );
    writeJson(
      p.join(sessionDir, documentsDirName, documentFileName(documentId)),
      Document(
        id: documentId,
        sessionId: sessionId,
        value: const {'branch': 'main'},
      ).toJson(),
    );
    File(p.join(sessionDir, eventsFileName)).writeAsStringSync(
      '${jsonEncode(SessionStarted(time: time, code: null).toJson())}\n',
    );
    stepDir = p.join(
      sessionDir,
      stepsDirName,
      stepDirName(time, 'collect', stepId),
    );
    writeJson(
      p.join(stepDir, stepFileName),
      Step(
        id: stepId,
        sessionId: sessionId,
        name: 'collect',
        key: 'collect#1@0000000000000000',
        after: null,
        place: 'lib/review.dart:22',
        outputId: null,
        log: logFileName,
      ).toJson(),
    );
    File(p.join(stepDir, logFileName)).writeAsStringSync('collecting\n');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('reads a step\'s log and documents, and tells their files once the '
      'feed has given them', () async {
    final reader = FsReader(runsDir: runsDir);
    final StepFiles files = ReaderFiles(reader);

    expect(await files.documentValue(sessionId, documentId), {
      'branch': 'main',
    });
    expect(await files.stepLog(sessionId, stepId).first, 'collecting\n');
    expect(files.logPath(stepId), isNull);
    expect(files.stepPath(stepId), isNull);

    final changes = reader.changes().listen(null);
    addTearDown(changes.cancel);
    // The feed gives a session's documents after its steps.
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
