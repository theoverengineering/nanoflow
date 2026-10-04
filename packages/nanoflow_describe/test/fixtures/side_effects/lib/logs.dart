// Logs and waits, which the rule lets be anywhere: none warns.
import 'dart:async';
import 'dart:io';

import 'package:nanoflow/nanoflow.dart';

Future<void> logs(Flow f, String input) async {
  print('x');
  stdout.writeln('x');
  stderr.write('x');
  await Future<void>.delayed(Duration.zero);
  Timer(Duration.zero, () {});
  await f.effect('log', () => input);
}
