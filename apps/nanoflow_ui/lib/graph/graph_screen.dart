import 'dart:math' as math;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:nanoflow_model/nanoflow_model.dart' show GraphNode;

import '../platform/shell.dart';
import '../state/body_path.dart';
import '../state/clock.dart';
import '../state/graph_model.dart';
import '../theme.dart';
import 'canvas/graph_canvas.dart';
import 'graph_notes.dart';
import 'header.dart';
import 'session_bar.dart';
import 'sessions_column.dart';
import 'split_view.dart';

/// Opens the model of the graph file [file].
typedef OpenModel = GraphModel Function(String file);

/// One graph file's screen (docs/ui-spec.md «Экран графа», spec §9): the
/// header with the crumbs of the levels drawn, the sessions column, and the
/// canvas with the session bar and the notes on the graph (`GraphNotes`)
/// floating over it, the notes under the bar. The border of the column
/// moves.
///
/// A double click on a call draws its function's body, on copies the body
/// of a copy (`openings`); a call of an interface method first offers its
/// implementations.
///
/// The screen owns the [GraphModel] of its file: it opens it as it opens,
/// and disposes it, with what follows the files, when it is left or the
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

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  late final GraphModel _model;
  late final LiveClock _clock;
  late final AppLifecycleListener _lifecycle;
  final _canvas = GraphCanvasController();
  bool _closed = false;

  /// How tall the notes over the canvas are; 0 without any.
  double _notesHeight = 0;

  /// Where the session bar and the notes float over the canvas: clear of
  /// the zoom buttons at the bottom.
  static const _overCanvas = EdgeInsets.fromLTRB(16, 12, 16, 60);

  /// The gap between the session bar and the notes under it.
  static const _barGap = 8.0;

  @override
  void initState() {
    super.initState();
    _model = widget.openModel(widget.path);
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

  /// A double click on [node] at [position]: draws what it opens; for a
  /// call of several functions, the one chosen from a menu there.
  Future<void> _openNode(GraphNode node, Offset position) async {
    final choices = openings(node, _model.canvas.file?.functions ?? const {});
    if (choices.isEmpty) return;
    if (choices.length == 1) return _model.open(choices.single);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final at = overlay.globalToLocal(position);
    final functionId = await showMenu<String>(
      context: context,
      color: AppColors.control,
      position: RelativeRect.fromLTRB(
        at.dx,
        at.dy,
        overlay.size.width - at.dx,
        overlay.size.height - at.dy,
      ),
      items: [
        for (final choice in choices)
          PopupMenuItem<String>(
            value: choice.functionId,
            height: 34,
            child: Text(
              functionTitle(choice.functionId!),
              style: AppText.button.copyWith(color: AppColors.textPrimary),
            ),
          ),
      ],
    );
    if (functionId == null || !mounted) return;
    _model.open(Opened(node.id, functionId: functionId));
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
          model: _model,
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
            second: ListenableBuilder(
              listenable: _model,
              builder: (context, _) => _overlaidCanvas(),
            ),
          ),
        ),
      ],
    ),
  );

  /// The canvas with the session bar over its top, and the notes under the
  /// bar; the graph is fitted clear of both.
  Widget _overlaidCanvas() {
    final notesTop =
        _overCanvas.top +
        (_model.selectedSession == null ? 0 : SessionBar.height + _barGap);
    return Stack(
      children: [
        Positioned.fill(
          child: GraphCanvas(
            model: _model,
            controller: _canvas,
            onOpenNode: _openNode,
            topInset: _notesHeight == 0
                ? GraphCanvas.sessionBarRoom
                : math.max(
                    GraphCanvas.sessionBarRoom,
                    notesTop + _notesHeight + _overCanvas.top,
                  ),
          ),
        ),
        Positioned(
          left: _overCanvas.left,
          top: _overCanvas.top,
          right: _overCanvas.right,
          child: SessionBar(model: _model, clock: _clock),
        ),
        Positioned.fill(
          child: Padding(
            padding: _overCanvas.copyWith(top: notesTop),
            child: GraphNotes(
              notes: _model.canvas.notes,
              onHeight: (height) => setState(() => _notesHeight = height),
            ),
          ),
        ),
      ],
    );
  }
}
