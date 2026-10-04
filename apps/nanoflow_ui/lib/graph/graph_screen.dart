import 'dart:math' as math;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:nanoflow_model/nanoflow_model.dart' show GraphNode, EffectNode;

import '../platform/shell.dart';
import '../state/body_path.dart';
import '../state/clock.dart';
import '../state/effect_details.dart';
import '../state/graph_model.dart';
import '../state/visits.dart';
import '../theme.dart';
import 'canvas/graph_canvas.dart';
import 'details/effect_details_window.dart';
import 'graph_notes.dart';
import 'header.dart';
import 'logs/logs_panel.dart';
import 'session_bar.dart';
import 'sessions_column.dart';
import 'split_view.dart';

/// Opens the model of the graph file [file].
typedef OpenModel = GraphModel Function(String file);

/// One graph file's screen (docs/ui-spec.md «Экран графа», spec §9): the
/// header with the crumbs of the levels drawn, the sessions column, and the
/// canvas over the `Logs` panel, the session bar and the notes on the graph
/// (`GraphNotes`) floating over the canvas, the notes under the bar. The
/// borders of the column and of the panel move.
///
/// A double click on a call draws its function's body, on copies the body
/// of a copy (`openings`); a call of an interface method first offers its
/// implementations. The `+` on a call or copies draws that body in place,
/// in a frame (decision 6), the same way; the model keeps what is expanded
/// for any session of the workflow.
///
/// `Open` in `Logs` opens the effect details window over it all on the
/// selected effect; a double click on an effect node, on the node's last effect
/// among those shown, else on the node alone. The effect the window shows is
/// selected, so the canvas and `Logs` are on it once the window closes —
/// or, when it is the session's last effect, on its newest: following goes
/// on under the window, which stays on its effect.
///
/// The screen owns the [GraphModel] of its file: it opens it as it opens,
/// and disposes it, with what follows the files, when it is left or the
/// app quits; the app quits once the model has closed.
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

  /// How tall the notes over the canvas are; 0 without any.
  double _notesHeight = 0;

  /// Whether the `Logs` panel is folded to its title.
  bool _logsFolded = false;

  /// What the effect details window shows, while it is open: an effect, or an
  /// effect node without one.
  ({EffectNode? node, String? effectId})? _details;

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

  /// Lets the app quit once the model's feed has stopped: the Dart VM ends
  /// with the app and waits for what still runs in it, and the reader's
  /// watch of the processes that own sessions runs until the feed stops.
  Future<AppExitResponse> _quitting() async {
    await _model.close();
    _close();
    return AppExitResponse.exit;
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _model.dispose();
  }

  /// A double click on [node], a node of the body at [path], at
  /// [position]: draws what it opens; for a call of several functions, the
  /// one chosen from a menu there.
  Future<void> _openNode(
    List<Opened> path,
    GraphNode node,
    Offset position,
  ) async {
    final opened = await _opening(node, position);
    if (opened != null) _model.open(opened, from: path);
  }

  /// The `+` on [node], a node of the body at [path], at [position]:
  /// expands it in place as it opens; for a call of several functions, as
  /// the one chosen from a menu there. Whether it did: the menu may be
  /// left without a choice.
  Future<bool> _expandNode(
    List<Opened> path,
    GraphNode node,
    Offset position,
  ) async {
    final opened = await _opening(node, position);
    if (opened == null) return false;
    _model.expandNode(path, opened);
    return true;
  }

  /// How [node] opens: as it alone can, or as chosen from a menu at
  /// [position]; `null` when it opens nothing or nothing is chosen.
  Future<Opened?> _opening(GraphNode node, Offset position) async {
    final choices = openings(node, _model.canvas.file?.functions ?? const {});
    if (choices.isEmpty) return null;
    if (choices.length == 1) return choices.single;
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
    if (functionId == null || !mounted) return null;
    return Opened(node.id, functionId: functionId);
  }

  /// `Open` in `Logs`: the window on the selected [effect].
  void _openEffect(EffectDetails effect) =>
      setState(() => _details = (node: null, effectId: effect.effectId));

  /// A double click on the effect node [node] — of the frame drawn in place
  /// at [path], when given: the window on the effect it opens on, which is
  /// selected; on the node alone when it has none.
  void _openEffectNode(EffectNode node, List<Opened>? path) {
    final visit = _model.visitToOpen(node, path: path);
    if (visit != null) _model.showVisit(visit.effectId);
    setState(() => _details = (node: node, effectId: visit?.effectId));
  }

  /// Shows [visit] in the window, and selects it.
  void _showVisit(Visit visit) {
    _model.showVisit(visit.effectId);
    setState(() => _details = (node: _details?.node, effectId: visit.effectId));
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
              child: EffectDetailsWindow(
                model: _model,
                clock: _clock,
                shell: widget.shell,
                graphFile: widget.path,
                node: details.node,
                effectId: details.effectId,
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
          second: SplitView(
            axis: Axis.vertical,
            sized: SplitPane.second,
            extent: 280,
            minExtent: 120,
            maxExtent: double.infinity,
            minOther: 200,
            border: AppColors.panelBorder,
            fixedExtent: _logsFolded ? LogsPanel.foldedExtent : null,
            first: ListenableBuilder(
              listenable: _model,
              builder: (context, _) => _overlaidCanvas(),
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
              onOpenEffect: _openEffect,
            ),
          ),
        ),
      ),
    ],
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
            now: _clock.now,
            controller: _canvas,
            onOpenNode: _openNode,
            onOpenEffect: _openEffectNode,
            onExpandNode: _expandNode,
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
