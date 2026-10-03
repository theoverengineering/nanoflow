import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../platform/home_path.dart';
import '../platform/shell.dart';
import '../state/graph_file_source.dart';
import '../state/graph_model.dart';
import '../theme.dart';
import '../widgets/clickable.dart';
import '../widgets/dot.dart';
import '../widgets/failure_note.dart';
import '../widgets/icons.dart';

/// The graph screen's header (docs/ui-spec.md «Экран графа», spec §9
/// «Граф»): `Graphs` back to the start screen, the graph file's name, then
/// the crumbs of the levels drawn (`release › publish() › upload()`) and the
/// file's directory; on the right the [LiveBadge], `Reveal in Finder` and
/// `Open in editor` for the graph file. When Finder or the editor fails, a
/// note says so for a while.
///
/// The first crumb is the workflow drawn: with more than one to choose
/// from, it opens the list of workflows. A crumb above the body drawn goes
/// back up to its level.
class GraphHeader extends StatelessWidget {
  const GraphHeader({
    super.key,
    required this.path,
    required this.model,
    required this.shell,
    required this.onBack,
  });

  /// The key of the workflow crumb that opens the list of workflows.
  static const workflowKey = ValueKey('workflow picker');

  /// The graph file.
  final String path;

  /// What the screen shows: its workflows and levels, its graph file for
  /// the [LiveBadge].
  final GraphModel model;

  final Shell shell;

  /// Goes back to the start screen.
  final VoidCallback onBack;

  Future<void> _open(
    BuildContext context,
    Future<bool> Function(String path) open,
    String failure,
  ) async {
    if (await open(path) || !context.mounted) return;
    showFailureNote(context, failure);
  }

  @override
  Widget build(BuildContext context) {
    final name = p.basename(path);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.window,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: ListenableBuilder(
        listenable: model,
        builder: (context, _) {
          final crumbs = _crumbs();
          return Row(
            // The mockup's flex gap, round the free space too.
            spacing: 10,
            children: [
              Clickable(
                onTap: onBack,
                child: Text('Graphs', style: AppText.crumb),
              ),
              Text('/', style: AppText.crumbSeparator),
              Text(
                name,
                style: crumbs.isEmpty ? AppText.headerTitle : AppText.crumb,
              ),
              if (crumbs.isNotEmpty) ...[
                Text('/', style: AppText.crumbSeparator),
                ...crumbs,
              ],
              Expanded(
                child: Text(
                  abbreviateHome(p.dirname(path)),
                  style: AppText.headerPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              LiveBadge(source: model.graphFile),
              _Button(
                'Reveal in Finder',
                onTap: () => _open(
                  context,
                  shell.revealInFinder,
                  'Could not reveal $name in Finder',
                ),
              ),
              _Button(
                'Open in editor',
                onTap: () => _open(
                  context,
                  shell.openInEditor,
                  'Could not open $name in an editor',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The crumbs of the levels drawn, `›` between them: the last bold, the
  /// others leading back up; the workflow's the picker when there are
  /// workflows to choose from. Only the workflow's while it has nothing
  /// drawn; none without a workflow.
  List<Widget> _crumbs() {
    final workflow = model.workflow;
    if (workflow == null) return const [];
    final levels = model.canvas.levels;
    final titles = levels.isEmpty
        ? [workflow.name]
        : [for (final level in levels) level.title];
    final picker = model.workflows.length > 1;
    return [
      for (var i = 0; i < titles.length; i++) ...[
        if (i > 0) Text('›', style: AppText.crumbSeparator),
        _crumb(
          Text(
            titles[i],
            style: i == titles.length - 1 ? AppText.headerTitle : AppText.crumb,
          ),
          picker: i == 0 && picker,
          up: i < titles.length - 1 ? () => model.openLevel(i) : null,
        ),
      ],
    ];
  }

  /// A crumb of [title]: the workflow picker, or one going [up].
  Widget _crumb(Widget title, {required bool picker, VoidCallback? up}) {
    if (picker) return _WorkflowPicker(model: model, child: title);
    if (up == null) return title;
    return Clickable(onTap: up, child: title);
  }
}

/// The workflow crumb with a chevron down: a click lists the workflows to
/// choose from, those of the graph file and then those only sessions ran,
/// marked; the workflow chosen is drawn from its top level.
class _WorkflowPicker extends StatelessWidget {
  const _WorkflowPicker({required this.model, required this.child});

  final GraphModel model;
  final Widget child;

  Future<void> _pick(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(
      Offset(0, box.size.height + 4),
      ancestor: overlay,
    );
    final chosen = model.workflow?.id;
    final id = await showMenu<String>(
      context: context,
      color: AppColors.control,
      position: RelativeRect.fromLTRB(
        at.dx,
        at.dy,
        overlay.size.width - at.dx,
        0,
      ),
      items: [
        for (final workflow in model.workflows)
          PopupMenuItem<String>(
            value: workflow.id,
            height: 34,
            child: Row(
              spacing: 8,
              children: [
                Text(
                  workflow.name,
                  style: AppText.button.copyWith(
                    color: workflow.id == chosen
                        ? AppColors.accentText
                        : AppColors.textPrimary,
                  ),
                ),
                if (!workflow.inGraphFile)
                  Text('not in the graph file', style: AppText.hint),
              ],
            ),
          ),
      ],
    );
    if (id != null) model.selectWorkflow(id);
  }

  @override
  Widget build(BuildContext context) => Clickable(
    key: GraphHeader.workflowKey,
    onTap: () => _pick(context),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 5,
      children: [
        child,
        const ChevronIcon(size: 12, color: AppColors.textDim, down: true),
      ],
    ),
  );
}

/// Whether what the screen shows is live: `Live · watching runs/`. The
/// `runs` directory is always watched; the graph file is live while it is
/// there and can be read, else the badge says which is wrong.
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key, required this.source});

  final GraphFileSource source;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: source,
    builder: (context, _) {
      final error = source.error;
      final (state, dot, fill, border, text) = source.fileMissing
          ? (
              fileUnavailable,
              AppColors.failed,
              AppColors.dangerSurface,
              AppColors.dangerBorder,
              AppColors.dangerText,
            )
          : error != null
          ? (
              unreadableFile,
              AppColors.failed,
              AppColors.dangerSurface,
              AppColors.dangerBorder,
              AppColors.dangerText,
            )
          : (
              'Live',
              AppColors.finished,
              AppColors.finishedSurface,
              AppColors.finishedBorder,
              AppColors.finishedText,
            );
      final badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 7,
          children: [
            Dot(dot),
            Text(
              '$state · watching runs/',
              style: AppText.liveBadge.copyWith(color: text),
            ),
          ],
        ),
      );
      return error == null || source.fileMissing
          ? badge
          : Tooltip(message: error, child: badge);
    },
  );
}

/// What the [LiveBadge] says of a graph file that cannot be read.
const unreadableFile = 'File unreadable';

/// A header button: `Reveal in Finder`, `Open in editor`.
class _Button extends StatelessWidget {
  const _Button(this.label, {required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Clickable(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.control,
        border: Border.all(color: AppColors.controlBorder),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(label, style: AppText.button),
    ),
  );
}
