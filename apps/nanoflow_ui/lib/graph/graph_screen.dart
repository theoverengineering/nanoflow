import 'dart:math' as math;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import '../platform/shell.dart';
import '../state/clock.dart';
import '../state/graph_model.dart';
import '../state/step_details.dart';
import '../state/visits.dart';
import '../theme.dart';
import 'canvas/graph_canvas.dart';
import 'details/step_details_window.dart';
import 'graph_errors.dart';
import 'header.dart';
import 'logs/logs_panel.dart';
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
/// `Open` in `Logs` opens the step details window over it all on the
/// selected step; a double click on a node, on the node's last visit in the
/// selected run, else its latest in the session, else on its description
/// alone. The visit the window shows is selected, so the canvas and `Logs`
/// are on it once the window closes — or, when it is the last step of a
/// running run, on that run's newest step: following goes on under the
/// window, which stays on its visit.
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
  final _canvas = GraphCanvasController();
  bool _closed = false;

  /// Whether the `Logs` panel is folded to its title.
  bool _logsFolded = false;

  /// How tall the problems over the canvas are; 0 without any.
  double _problemsHeight = 0;

  /// Where the problems and the session bar float over the canvas.
  static const _overCanvas = EdgeInsets.fromLTRB(16, 12, 16, 60);

  /// What the step details window shows, while it is open: a node, at the
  /// visit of a step or without one.
  ({String node, String? stepId})? _details;

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

  /// `Open` in `Logs`: the window on the selected [step].
  void _openStep(StepDetails step) =>
      setState(() => _details = (node: step.node, stepId: step.stepId));

  /// A double click on [node]: the window on the visit it opens on, which is
  /// selected; on the node's description when it has none.
  void _openNode(String node) {
    final visit = _model.visitToOpen(node);
    if (visit != null) _model.showVisit(visit.stepId);
    setState(() => _details = (node: node, stepId: visit?.stepId));
  }

  /// Shows [visit] in the window, and selects it.
  void _showVisit(Visit visit) {
    _model.showVisit(visit.stepId);
    setState(() => _details = (node: visit.node, stepId: visit.stepId));
  }

  void _closeDetails() => setState(() => _details = null);

  @override
  void dispose() {
    _lifecycle.dispose();
    _close();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final details = _details;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _screen()),
          if (details != null)
            Positioned.fill(
              child: StepDetailsWindow(
                model: _model,
                clock: _clock,
                shell: widget.shell,
                graphFile: widget.path,
                node: details.node,
                stepId: details.stepId,
                onVisit: _showVisit,
                onClose: _closeDetails,
              ),
            ),
        ],
      ),
    );
  }

  Widget _screen() => Column(
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
            fixedExtent: _logsFolded ? LogsPanel.foldedExtent : null,
            first: Stack(
              children: [
                Positioned.fill(
                  child: GraphCanvas(
                    model: _model,
                    now: _clock.now,
                    controller: _canvas,
                    onOpenStep: _openNode,
                    // The graph is fitted clear of the problems too.
                    topInset: math.max(
                      GraphCanvas.sessionBarRoom,
                      _problemsHeight == 0
                          ? 0
                          : _overCanvas.top * 2 + _problemsHeight,
                    ),
                  ),
                ),
                Positioned(
                  left: _overCanvas.left,
                  top: _overCanvas.top,
                  right: _overCanvas.right,
                  child: SessionBar(model: _model, clock: _clock),
                ),
                // Clear of the zoom buttons.
                Positioned.fill(
                  child: Padding(
                    padding: _overCanvas,
                    child: GraphProblems(
                      model: _model,
                      onHeight: (height) =>
                          setState(() => _problemsHeight = height),
                    ),
                  ),
                ),
              ],
            ),
            second: LogsPanel(
              key: GraphScreen.logsKey,
              model: _model,
              clock: _clock,
              shell: widget.shell,
              graphFile: widget.path,
              collapsed: _logsFolded,
              onToggle: () => setState(() => _logsFolded = !_logsFolded),
              onRevealNode: _canvas.revealNode,
              onOpenStep: _openStep,
            ),
          ),
        ),
      ),
    ],
  );
}
