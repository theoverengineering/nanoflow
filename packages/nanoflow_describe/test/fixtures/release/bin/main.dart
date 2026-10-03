// Releases the version given as the first argument, or goes on with the
// session given after --resume.
import 'package:nanoflow/nanoflow.dart';

// A fixture has no pubspec.yaml, so its lib/ has no package: URI.
// ignore: avoid_relative_lib_imports
import '../lib/release.dart';

Future<void> main(List<String> args) async {
  final flow = Flow();
  final session = args.first == '--resume'
      ? await flow.resume(release, args[1])
      : await flow.start(release, args.first);
  print(session.id);
  await session.result;
}
