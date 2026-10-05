// Runs each workflow of lib/calls.dart once, as a session in runs/ of
// [directory].
import 'package:nanoflow/nanoflow.dart';

import 'calls.dart';

/// Runs release and inPlace on the stable channel, one after the other, as
/// sessions in runs/ of [directory].
Future<void> runAll(String directory) async {
  final flow = Flow(directory: directory);
  await flow.run(release, 'stable');
  await flow.run(inPlace, 'stable');
}
