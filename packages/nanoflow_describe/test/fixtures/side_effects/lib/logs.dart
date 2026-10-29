// Logs and waits, which the rule lets be anywhere: none warns.
import 'dart:async';
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';

final log = node('log', (String input) async => input);

final logs = Graph<String, void>('logs', [
  Graph.start(log).next((input) {
    print('x');
    stdout.writeln('x');
    stderr.write('x');
    unawaited(Future<void>.delayed(Duration.zero));
    Timer(Duration.zero, () {});
    return null;
  }),
]);
