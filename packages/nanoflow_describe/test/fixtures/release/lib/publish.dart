// A function with steps that the release calls for every public package.
import 'package:nanoflow/nanoflow.dart';

class Package {
  Package(this.name, this.isPublic);
  final String name;
  final bool isPublic;
}

/// Uploads [p] and takes it back when it does not verify.
Future<void> publish(Flow f, Package p) async {
  await f.step('upload', () => print('upload ${p.name}'));
  final ok = await f.step('verify', () => p.name.isNotEmpty);
  if (!ok) await f.step('rollback', () => print('rollback ${p.name}'));
}
