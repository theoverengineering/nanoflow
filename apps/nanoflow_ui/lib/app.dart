import 'dart:async';

import 'package:flutter/material.dart';

import 'graph/graph_screen.dart';
import 'platform/shell.dart';
import 'start/launch.dart';
import 'start/recent_graphs.dart';
import 'start/start_screen.dart';
import 'state/graph_model.dart';
import 'state/store_place.dart';
import 'theme.dart';
import 'widgets/failure_note.dart';

/// The app: it starts on the start screen — or on the graph it was started
/// with ([launch]) —, opens one graph at a time, and the graph screen's
/// `Graphs` leads back.
class NanoflowApp extends StatelessWidget {
  const NanoflowApp({
    super.key,
    required this.recent,
    required this.shell,
    this.launch,
    this.launchError,
    this.pickFile = pickGraphFile,
    this.exists = fileExists,
    this.now = DateTime.now,
    this.openModel = GraphModel.open,
  });

  final RecentGraphs recent;
  final Shell shell;

  /// The graph the app was started with; `null` for the start screen.
  final Launch? launch;

  /// What is wrong with the command line, shown on the start screen.
  final String? launchError;

  final PickFile pickFile;
  final bool Function(String path) exists;
  final DateTime Function() now;

  /// Opens the model of a graph the user opens.
  final OpenModel openModel;

  @override
  Widget build(BuildContext context) => appFrame(home: _Screens(this));
}

class _Screens extends StatefulWidget {
  const _Screens(this.app);

  final NanoflowApp app;

  @override
  State<_Screens> createState() => _ScreensState();
}

class _ScreensState extends State<_Screens> {
  /// The open graph file, the store of its sessions and the session to
  /// select; none on the start screen.
  Launch? _graph;

  @override
  void initState() {
    super.initState();
    final app = widget.app;
    if (app.launch case final launch?) {
      _graph = launch;
      unawaited(app.recent.opened(launch.path, app.now(), store: launch.store));
    }
    if (app.launchError case final error?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showFailureNote(context, error);
      });
    }
  }

  void _open(String path, {StorePlace? store}) {
    unawaited(widget.app.recent.opened(path, widget.app.now(), store: store));
    setState(() => _graph = (path: path, store: store, session: null));
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final graph = _graph;
    if (graph == null) {
      return StartScreen(
        recent: app.recent,
        onOpen: _open,
        pickFile: app.pickFile,
        exists: app.exists,
        now: app.now,
      );
    }
    return GraphScreen(
      key: ValueKey(graph),
      path: graph.path,
      store: graph.store,
      session: graph.session,
      shell: app.shell,
      onBack: () => setState(() => _graph = null),
      openModel: app.openModel,
    );
  }
}
