import 'dart:async';

import 'package:flutter/material.dart';

import 'graph/graph_screen.dart';
import 'platform/shell.dart';
import 'start/recent_graphs.dart';
import 'start/start_screen.dart';
import 'theme.dart';

/// The MaterialApp around every screen; golden tests show screens in it too.
Widget appFrame({required Widget home}) => MaterialApp(
  title: 'nanoflow',
  theme: nanoflowTheme(),
  debugShowCheckedModeBanner: false,
  home: home,
);

/// The app: it starts on the start screen, opens one graph at a time, and
/// the graph screen's `Graphs` leads back.
class NanoflowApp extends StatelessWidget {
  const NanoflowApp({
    super.key,
    required this.recent,
    required this.shell,
    this.pickFile = pickGraphFile,
    this.exists = fileExists,
    this.now = DateTime.now,
  });

  final RecentGraphs recent;
  final Shell shell;
  final PickFile pickFile;
  final bool Function(String path) exists;
  final DateTime Function() now;

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
  /// The open graph file; none on the start screen.
  String? _graph;

  void _open(String path) {
    unawaited(widget.app.recent.opened(path, widget.app.now()));
    setState(() => _graph = path);
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
      path: graph,
      shell: app.shell,
      onBack: () => setState(() => _graph = null),
    );
  }
}
