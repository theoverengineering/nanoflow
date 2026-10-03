// Owns the session in the directory its argument names, as the process that
// runs it does, without the store: locks the byte at `ownerLockOffset` of the
// session's `.owner.lock`, writes itself into it as the owner — its pid and
// its start by the OS — prints `owning` and waits until it is killed.
// test/owner_process_test.dart runs it.
import 'dart:convert';
import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_process/nanoflow_process.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final file = await File(p.join(args.single, ownerLockFileName))
      .open(mode: FileMode.append);
  await file.lock(FileLock.exclusive, ownerLockOffset, ownerLockOffset + 1);
  final processes = MacProcesses();
  final owner = Owner(pid: pid, started: processes.startOf(pid));
  await processes.close();
  final record = utf8.encode(jsonEncode(owner.toJson()));
  await file.setPosition(0);
  await file.writeFrom(record);
  await file.truncate(record.length);
  print('owning');
  await stdin.drain<void>();
}
