import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../platform/shell.dart';
import '../../state/step_details.dart';
import '../../state/step_files.dart';
import '../../theme.dart';
import '../../widgets/clickable.dart';
import 'document_view.dart';
import 'file_footer.dart';
import 'log_view.dart';

/// A tab of the step details.
enum StepTab { input, output, log }

/// The selected step's details on the right of the `Logs` panel
/// (docs/ui-spec.md «Logs»: «Детали шага»): the node's name, the tabs
/// `Input`, `Output` and `Log`, and `Open` for the step details window.
///
/// A tab whose data the node does not declare is marked `—`. `Input` and
/// `Output` show their document as JSON, `Log` the step's log; the open tab
/// stays as other steps are selected, `Log` at first. While the log of a
/// running step holds on to its end, `following tail` says so. With files
/// to point at, the open tab's file is at the bottom.
class StepDetailsPane extends StatefulWidget {
  const StepDetailsPane({
    super.key,
    required this.step,
    required this.files,
    required this.shell,
    required this.graphFile,
    this.onOpenStep,
  });

  final StepDetails step;
  final StepFiles files;
  final Shell shell;

  /// The graph file: the paths of files are shown from its directory.
  final String graphFile;

  /// Opens the step details window on the step.
  final ValueChanged<StepDetails>? onOpenStep;

  static Key tabKey(StepTab tab) => ValueKey(('step tab', tab));
  static const headerKey = ValueKey('step details header');
  static const followingKey = ValueKey('following tail');
  static const openKey = ValueKey('open step');

  @override
  State<StepDetailsPane> createState() => _StepDetailsPaneState();
}

class _StepDetailsPaneState extends State<StepDetailsPane> {
  StepTab _tab = StepTab.log;

  /// Whether the log holds on to its end: anew for each log view, which
  /// opens at the end.
  ValueNotifier<bool> _following = ValueNotifier(true);

  static bool _same(StepDetails a, StepDetails b) =>
      a.sessionId == b.sessionId && a.runId == b.runId && a.stepId == b.stepId;

  @override
  void didUpdateWidget(StepDetailsPane old) {
    super.didUpdateWidget(old);
    if (!_same(old.step, widget.step)) _followAnew();
  }

  /// A new flag for a new log view: one that holds on. Replaced rather than
  /// set, so that nothing hears of it while the frame is built.
  void _followAnew() {
    final previous = _following;
    // The old log view lets go of it as the next frame is built.
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    _following = ValueNotifier(true);
  }

  void _open(StepTab tab) => setState(() {
    if (tab == StepTab.log && _tab != StepTab.log) _followAnew();
    _tab = tab;
  });

  @override
  void dispose() {
    _following.dispose();
    super.dispose();
  }

  /// The file of the open tab, when there are files.
  String? get _path {
    final step = widget.step;
    final files = widget.files;
    String? document(StepDocument data) => switch (data.documentId) {
      final id? => files.documentPath(step.sessionId, id),
      null => null,
    };
    return switch (_tab) {
      StepTab.log => files.logPath(step.stepId),
      StepTab.input => document(step.input),
      StepTab.output => document(step.output),
    };
  }

  Widget _body() {
    final step = widget.step;
    StepDocument data;
    switch (_tab) {
      case StepTab.log:
        return LogView(
          key: ValueKey(('log', step.sessionId, step.runId, step.stepId)),
          files: widget.files,
          step: step,
          following: _following,
        );
      case StepTab.input:
        data = step.input;
      case StepTab.output:
        data = step.output;
    }
    final id = data.documentId;
    return id == null
        ? TabNote(data.message ?? '')
        : DocumentView(
            key: ValueKey(('document', step.sessionId, id)),
            files: widget.files,
            sessionId: step.sessionId,
            documentId: id,
          );
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    final path = _path;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          step: step,
          tab: _tab,
          following: _following,
          onTab: _open,
          onOpen: () => widget.onOpenStep?.call(step),
        ),
        Expanded(child: _body()),
        if (path != null)
          FileFooter(
            path: path,
            root: p.dirname(widget.graphFile),
            shell: widget.shell,
          ),
      ],
    );
  }
}

/// The node's name, the tabs, `following tail` and `Open`.
class _Header extends StatelessWidget {
  const _Header({
    required this.step,
    required this.tab,
    required this.following,
    required this.onTab,
    required this.onOpen,
  });

  final StepDetails step;
  final StepTab tab;
  final ValueNotifier<bool> following;
  final ValueChanged<StepTab> onTab;
  final VoidCallback onOpen;

  /// Narrower than this, `following tail` is only its dot.
  static const _roomForBadge = 440.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Container(
      key: StepDetailsPane.headerKey,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              spacing: 4,
              children: [
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      step.node,
                      style: AppText.detailsTitle,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                for (final (which, label, marked) in [
                  (StepTab.input, 'Input', step.input.marked),
                  (StepTab.output, 'Output', step.output.marked),
                  (StepTab.log, 'Log', false),
                ])
                  _Tab(
                    which: which,
                    label: label,
                    marked: marked,
                    selected: which == tab,
                    onTap: () => onTab(which),
                  ),
              ],
            ),
          ),
          if (tab == StepTab.log && step.running)
            ValueListenableBuilder(
              valueListenable: following,
              builder: (context, following, _) => following
                  ? Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: _FollowingBadge(
                        compact: constraints.maxWidth < _roomForBadge,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          const SizedBox(width: 10),
          Clickable(
            onTap: onOpen,
            child: Semantics(
              label: 'Open step in details view',
              child: Container(
                key: StepDetailsPane.openKey,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.control,
                  border: Border.all(color: AppColors.controlBorder),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Open', style: AppText.smallButton),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A tab: filled when [selected]; `—` after a [marked] one's label.
class _Tab extends StatelessWidget {
  const _Tab({
    required this.which,
    required this.label,
    required this.marked,
    required this.selected,
    required this.onTap,
  });

  final StepTab which;
  final String label;
  final bool marked;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = selected
        ? AppText.tab.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          )
        : AppText.tab.copyWith(
            color: marked ? AppColors.textFaint : AppColors.textMuted,
          );
    return Clickable(
      onTap: onTap,
      child: Container(
        key: StepDetailsPane.tabKey(which),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: selected
            ? BoxDecoration(
                color: AppColors.selectedTab,
                borderRadius: BorderRadius.circular(6),
              )
            : null,
        child: Text.rich(
          TextSpan(
            text: label,
            children: [
              if (marked)
                TextSpan(
                  text: ' —',
                  style: style.copyWith(
                    color: AppColors.textDim,
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ],
          ),
          style: style,
          maxLines: 1,
          softWrap: false,
        ),
      ),
    );
  }
}

/// `following tail`: an amber dot and the words, or the dot alone when
/// [compact], the words in a tooltip.
class _FollowingBadge extends StatelessWidget {
  const _FollowingBadge({required this.compact});

  final bool compact;

  static const _text = 'following tail';

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      key: StepDetailsPane.followingKey,
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 9, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.noteSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.running,
              shape: BoxShape.circle,
            ),
          ),
          if (!compact) Text(_text, style: AppText.noteBadge),
        ],
      ),
    );
    return compact ? Tooltip(message: _text, child: badge) : badge;
  }
}
