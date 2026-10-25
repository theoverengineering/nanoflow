// Tries to own the session its arguments name — the runs directory and the
// session's id — and prints `busy` when another process owns it, `opened`
// when it could own it. test/fs_store_test.dart runs it.
import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_store/nanoflow_store.dart';

Future<void> main(List<String> args) async {
  try {
    final handle = await FsStore(args[0]).openSession(args[1]);
    await handle!.release();
    print('opened');
  } on SessionBusyException {
    print('busy');
  }
}
