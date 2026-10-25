import 'dart:io';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_process/nanoflow_process.dart';
import 'package:nanoflow_reader/nanoflow_reader.dart';
import 'package:nanoflow_store/nanoflow_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The adapters every test runs on, by the scheme of their places.
const schemes = ['fs'];

/// A place of a storage, as nanoflow_ui names it: `fs:<runs directory>` or
/// `sqlite:<database file>`. The tests and the programs they run name the
/// storage they share this way.
typedef Place = String;

/// A fresh place of [scheme] in a temporary directory, deleted after the
/// test.
Place freshPlace(String scheme) {
  final dir = Directory.systemTemp
      .createTempSync('nanoflow_contract_')
      .resolveSymbolicLinksSync();
  addTearDown(() => Directory(dir).deleteSync(recursive: true));
  return switch (scheme) {
    'fs' => 'fs:${p.join(dir, 'runs')}',
    _ => throw ArgumentError.value(scheme, 'scheme'),
  };
}

/// The store of the storage at [place].
SessionStore storeAt(Place place) => switch (_split(place)) {
  ('fs', final path) => FsStore(path),
  _ => throw ArgumentError.value(place, 'place'),
};

/// A reader of the storage at [place] that looks every 20 ms, and asks
/// [processes] whether owners are alive: by default the adapter of this OS.
SessionReader readerAt(Place place, {Processes? processes}) =>
    switch (_split(place)) {
      ('fs', final path) => FsReader(
        runsDir: path,
        pollInterval: const Duration(milliseconds: 20),
        processes: processes,
      ),
      _ => throw ArgumentError.value(place, 'place'),
    };

/// This process as the owner of a session, with its start by the OS.
Owner thisProcess() {
  final processes = Processes.forPlatform();
  try {
    return Owner(pid: pid, started: processes.startOf(pid));
  } finally {
    processes.close().ignore();
  }
}

(String, String) _split(Place place) {
  final colon = place.indexOf(':');
  return (place.substring(0, colon), place.substring(colon + 1));
}
