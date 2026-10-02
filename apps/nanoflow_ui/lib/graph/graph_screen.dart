import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import '../platform/shell.dart';
import '../state/clock.dart';
import '../state/graph_model.dart';
import '../theme.dart';
import 'canvas/graph_canvas.dart';
import 'graph_errors.dart';
import 'header.dart';
import 'session_bar.dart';
import 'sessions_column.dart';
import 'split_view.dart';

/// Opens the model of the graph file [file], starting programs with [shell].
typedef OpenModel = GraphModel Function(String file, Shell shell);

/// One graph file's screen (docs/ui-spec.md «Экран графа»): the header, the
/// sessions column, and the canvas over the `Logs` panel, the session bar
/// and what is wrong with the current graph floating over the canvas. The
/// borders of the column and of the panel move.
///
/// The screen owns the [GraphModel] of its file: it opens it as it opens,
/// and disposes it, with the programs it started, when it is left or the
/// app quits.
class GraphScreen extends StatefulWidget {
  const GraphScreen({
    super.key,
    required this.path,
    required this.shell,
    required this.onBack,
    this.openModel = GraphModel.open,
    this.now,
  });

  /// The graph file.
  final String path;

  /// How the screen reaches macOS.
  final Shell shell;

  /// Goes back to the start screen.
  final VoidCallback onBack;

  /// Opens the screen's model: by default the live one of the graph file.
  final OpenModel openModel;

  /// The time; by default the wall clock.
  final DateTime Function()? now;

  /// The key of the `Logs` panel.
  static const logsKey = ValueKey('logs');

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  late final GraphModel _model;
  late final LiveClock _clock;
  late final AppLifecycleListener _lifecycle;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _model = widget.openModel(widget.path, widget.shell);
    _clock = LiveClock(now: widget.now);
    // Quitting the app does not dispose the screen.
    _lifecycle = AppLifecycleListener(onExitRequested: _quitting);
  }

  Future<AppExitResponse> _quitting() async {
    _close();
    return AppExitResponse.exit;
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _model.dispose();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _close();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GraphHeader(
          path: widget.path,
          source: _model.source,
          shell: widget.shell,
          onBack: widget.onBack,
        ),
        Expanded(
          child: SplitView(
            axis: Axis.horizontal,
            sized: SplitPane.first,
            extent: 272,
            minExtent: 200,
            maxExtent: 480,
            minOther: 480,
            border: AppColors.divider,
            first: SessionsColumn(
              model: _model,
              clock: _clock,
              graphFile: widget.path,
            ),
            second: SplitView(
              axis: Axis.vertical,
              sized: SplitPane.second,
              extent: 280,
              minExtent: 120,
              maxExtent: double.infinity,
              minOther: 200,
              border: AppColors.panelBorder,
              first: Stack(
                children: [
                  Positioned.fill(
                    child: GraphCanvas(model: _model, now: _clock.now),
                  ),
                  Positioned(
                    left: 16,
                    top: 12,
                    right: 16,
                    child: SessionBar(model: _model, clock: _clock),
                  ),
                  // Clear of the zoom buttons.
                  Positioned(
                    left: 16,
                    top: 12,
                    right: 16,
                    bottom: 60,
                    child: GraphProblems(model: _model),
                  ),
                ],
              ),
              second: const _Logs(key: GraphScreen.logsKey),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The `Logs` panel under the canvas: for now only its title.
class _Logs extends StatelessWidget {
  const _Logs({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.panel,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: Text('Logs', style: AppText.logsTitle),
        ),
      ],
    ),
  );
}
