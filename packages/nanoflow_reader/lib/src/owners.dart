import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nanoflow_model/nanoflow_model.dart';
import 'package:nanoflow_process/nanoflow_process.dart';

/// What became of the process of an owner that is watched.
enum Fate {
  /// It exited.
  exited,

  /// Watching it failed: whether it runs cannot be known.
  unknown,
}

/// The owners of the sessions whose journal goes on, as their `.owner.lock`
/// records them, and whether their processes run: what `owner-changed` tells
/// (design §5).
///
/// An owner is a pid and the time its process started. The exit of a new
/// owner's process is watched with [Processes.exitOf] before its start is
/// compared with [Processes.startOf]: a process that exits in between is
/// told gone all the same. An exit, or a watch that fails, is told on
/// [news]; a scan after it tells the session's owner not alive, or alive
/// unknown, once it has read the journal that process wrote.
final class Owners {
  Owners(this._processes);

  final Processes _processes;

  /// The sessions whose owner has been told, by id.
  final Map<String, _Told> _sessions = {};

  final StreamController<void> _news = StreamController<void>();

  bool _closed = false;

  /// An event each time the process of an owner that is watched exits, or
  /// watching it fails.
  Stream<void> get news => _news.stream;

  /// What has become of the process of the owner of the session [sessionId]
  /// so far: `null` while it runs, or when it is not watched.
  ///
  /// A scan takes it before it reads the session's journal: then the journal
  /// holds all that a process that exited wrote.
  Fate? fateOf(String sessionId) => _sessions[sessionId]?.watch?.fate;

  /// Reads the owner of the session [sessionId] from its `.owner.lock` at
  /// [lockFile] and gives `owner-changed` to [out] when the owner, or whether
  /// it is alive, differs from what was given last, or nothing was.
  ///
  /// A new owner is watched. The owner given before is not alive when its
  /// [fate], taken before the journal was read, is that it exited, and
  /// unknown when watching it failed.
  ///
  /// A file that is not there, or empty, records no owner. A file that does
  /// not hold an owner is being written, its new record over the old one:
  /// what was given stays, and the next scan reads it again. Throws an
  /// [IOException] when the file cannot be read.
  Future<void> update(
    String sessionId,
    String lockFile,
    Fate? fate,
    EventSink<Change> out,
  ) async {
    final record = await _read(lockFile);
    if (record == null) return;
    final told = _sessions[sessionId] ??= _Told();
    final last = told.change;
    final owner = record.owner;
    final alive = last == null || owner != last.owner
        ? _watch(sessionId, told, owner)
        : switch (fate) {
            null => last.alive,
            Fate.exited => false,
            Fate.unknown => null,
          };
    final change = OwnerChanged(
      sessionId: sessionId,
      owner: owner,
      alive: alive,
    );
    if (change == last) return;
    told.change = change;
    out.add(change);
  }

  /// Forgets the owner of the session [sessionId] and stops telling its
  /// exit: the session's journal has ended.
  void drop(String sessionId) => _sessions.remove(sessionId);

  /// Forgets every owner: nothing heard from now on is told.
  void close() {
    _closed = true;
    _sessions.clear();
    unawaited(_news.close());
  }

  /// Watches the process of [owner], the new owner of the session
  /// [sessionId] that [told] is of, and tells whether it is alive: `false`
  /// for no owner, and `null`, without watching, for an owner without a
  /// start or when [_processes] cannot tell.
  bool? _watch(String sessionId, _Told told, Owner? owner) {
    told.watch = null;
    if (owner == null) return false;
    if (owner.started == null || !_processes.supported) return null;
    final watch = told.watch = _Watch();
    unawaited(
      Future.sync(() => _processes.exitOf(owner.pid)).then(
        (_) => _heard(sessionId, watch, Fate.exited),
        onError: (Object _) => _heard(sessionId, watch, Fate.unknown),
      ),
    );
    return Owner(pid: owner.pid, started: _processes.startOf(owner.pid)) ==
        owner;
  }

  /// Takes the [fate] of the process [watch] waits for, and tells [news] when
  /// that is still the process of the owner of the session [sessionId].
  void _heard(String sessionId, _Watch watch, Fate fate) {
    watch.fate = fate;
    if (!_closed && _sessions[sessionId]?.watch == watch) _news.add(null);
  }
}

/// The owner the `.owner.lock` at [path] records: none when the file is not
/// there or empty, and `null` when it does not hold an owner, as while a new
/// record is written over the old one.
Future<({Owner? owner})?> _read(String path) async {
  final Uint8List bytes;
  try {
    bytes = await File(path).readAsBytes();
  } on PathNotFoundException {
    return (owner: null);
  }
  if (bytes.isEmpty) return (owner: null);
  try {
    if (jsonDecode(utf8.decode(bytes)) case final Map<String, Object?> json) {
      return (owner: Owner.fromJson(json));
    }
  } on FormatException {
    // Not JSON, or not an owner.
  }
  return null;
}

/// What has been told of the owner of a session.
final class _Told {
  /// The last `owner-changed` given; `null` before the first.
  OwnerChanged? change;

  /// The watch of the process of the owner told; `null` when it is not
  /// watched.
  _Watch? watch;
}

/// A wait for the exit of the process of an owner.
final class _Watch {
  /// What has become of the process; `null` while it runs.
  Fate? fate;
}
