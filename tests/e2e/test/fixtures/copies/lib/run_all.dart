// Runs each workflow of lib/copies.dart once, as a session in runs/ of
// [directory].
import 'package:nanoflow/nanoflow.dart';

import 'copies.dart';

/// Runs inPlace, viaMap and viaCall over core, tool and cli, and nested
/// over core and tool, one after another, as sessions in runs/ of
/// [directory].
Future<void> runAll(String directory) async {
  final flow = Flow(directory: directory);
  await flow.run(inPlace, packages);
  await flow.run(viaMap, packages);
  await flow.run(viaCall, packages);
  await flow.run(nested, packages.take(2).toList());
}
