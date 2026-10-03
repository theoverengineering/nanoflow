import 'dart:math' as math;

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
/// A crumb above the body drawn goes back up to its level; the chevron of
/// the workflow's crumb, when there are workflows to choose from, opens the
/// list of them. Crumbs that do not fit fold into `…` (`_Crumbs`).
class GraphHeader extends StatelessWidget {
  const GraphHeader({
    super.key,
    required this.path,
    required this.model,
    required this.shell,
    required this.onBack,
  });

  /// The key of the chevron that opens the list of workflows.
  static const workflowKey = ValueKey('workflow picker');

  /// The key of the crumb the middle crumbs of a deep path fold into.
  static const foldedKey = ValueKey('folded crumbs');

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
    final directory = Text(
      abbreviateHome(p.dirname(path)),
      style: AppText.headerPath,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
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
          final crumbs = model.workflow != null;
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
                style: crumbs ? AppText.headerFile : AppText.headerTitle,
              ),
              if (crumbs) Text('/', style: AppText.crumbSeparator),
              Expanded(
                child: crumbs
                    ? _Crumbs(model: model, directory: directory)
                    : directory,
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
}

/// The crumbs of the levels drawn, `›` between them, then [directory] in
/// what room is left: the last crumb bold, the others leading back up; the
/// workflow's with a chevron that lists the workflows when there are some
/// to choose from; only the workflow's while it has nothing drawn.
///
/// When they do not fit, the workflow's crumb and as many of the last as
/// fit stay, the ones between fold into `…`, which lists them; when even
/// those do not fit, the workflow's and the last are cut with `…`. Narrower
/// still, the workflow's crumb folds too — `… › last`, then the last alone
/// — and the chevron that lists the workflows stays in front.
class _Crumbs extends StatelessWidget {
  const _Crumbs({required this.model, required this.directory});

  final GraphModel model;
  final Widget directory;

  /// The gap round a separator, as in the header.
  static const _spacing = 10.0;

  /// The chevron's box: the icon and the room round it to click.
  static const _chevron = 20.0;
  static const _chevronGap = 2.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final levels = model.canvas.levels;
      final titles = levels.isEmpty
          ? [model.workflow!.name]
          : [for (final level in levels) level.title];
      final last = titles.length - 1;
      final picker = model.workflows.length > 1;
      final scaler = MediaQuery.textScalerOf(context);
      double widthOf(String text, TextStyle style) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        // A hair of room, so that what is measured is not cut when drawn.
        final width = painter.width + 1;
        painter.dispose();
        return width;
      }

      TextStyle styleOf(int i) =>
          i == last ? AppText.headerTitle : AppText.crumb;
      final texts = [
        for (var i = 0; i <= last; i++) widthOf(titles[i], styleOf(i)),
      ];
      final chevron = picker ? _chevronGap + _chevron : 0.0;
      final separator = widthOf('›', AppText.crumbSeparator) + 2 * _spacing;
      final fold = widthOf('…', AppText.crumb);
      // A crumb by its index; null for the fold. The workflows' chevron
      // goes with the workflow's crumb, or in front without it.
      double width(List<int?> shown) =>
          [for (final i in shown) i == null ? fold : texts[i]]
              .fold(0.0, (sum, w) => sum + w) +
          (shown.length - 1) * separator +
          chevron;
      // What of [shown] does not give way: all but the texts of the
      // workflow's crumb and the last.
      double fixed(List<int?> shown) =>
          width(shown) -
          [
            for (final i in shown)
              if (i == 0 || i == last) texts[i!],
          ].fold(0.0, (sum, w) => sum + w);

      // The gap before the directory is taken first.
      final room = math.max(0.0, constraints.maxWidth - _spacing);
      var shown = <int?>[for (var i = 0; i <= last; i++) i];
      if (width(shown) > room && last >= 2) {
        // The workflow's, the fold, and as many of the last as fit.
        var from = last;
        List<int?> keeping(int from) => [
          0,
          null,
          for (var i = from; i <= last; i++) i,
        ];
        while (from > 2 && width(keeping(from - 1)) <= room) {
          from--;
        }
        shown = keeping(from);
      }
      // Too narrow even to squeeze them: the fold and the last, or the last.
      if (last > 0 && fixed(shown) > room) {
        shown = fixed([null, last]) <= room ? [null, last] : [last];
      }
      final hidden = [
        for (var i = 0; i <= last; i++)
          if (!shown.contains(i)) i,
      ];
      return Row(
        spacing: _spacing,
        children: [
          SizedBox(
            width: math.min(width(shown), room),
            child: Row(
              children: [
                if (picker && !shown.contains(0)) ...[
                  _WorkflowPicker(model: model),
                  const SizedBox(width: _chevronGap),
                ],
                for (final (k, i) in shown.indexed) ...[
                  if (k > 0) ...[
                    const SizedBox(width: _spacing),
                    Text('›', style: AppText.crumbSeparator),
                    const SizedBox(width: _spacing),
                  ],
                  if (i == null)
                    _fold(context, titles, hidden)
                  else if (i == 0 || i == last)
                    // The ones that give way when nothing else does.
                    Flexible(
                      flex: math.max(1, texts[i].round()),
                      child: _crumb(titles[i], i, last),
                    )
                  else
                    _crumb(titles[i], i, last),
                  if (i == 0 && picker) ...[
                    const SizedBox(width: _chevronGap),
                    _WorkflowPicker(model: model),
                  ],
                ],
              ],
            ),
          ),
          Expanded(child: directory),
        ],
      );
    },
  );

  /// The crumb of the level [i] of [last] + 1, [title]: going up unless it
  /// is the last.
  Widget _crumb(String title, int i, int last) {
    final text = Text(
      title,
      style: i == last ? AppText.headerTitle : AppText.crumb,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
    return i < last
        ? Clickable(onTap: () => model.openLevel(i), child: text)
        : text;
  }

  /// `…` for the crumbs [hidden] of [titles]: a click lists them, and the
  /// one chosen goes back up to its level.
  Widget _fold(BuildContext context, List<String> titles, List<int> hidden) =>
      Builder(
        builder: (context) => Clickable(
          key: GraphHeader.foldedKey,
          onTap: () async {
            final depth = await showMenu<int>(
              context: context,
              color: AppColors.control,
              position: _below(context),
              items: [
                for (final i in hidden)
                  PopupMenuItem<int>(
                    value: i,
                    height: 34,
                    child: Text(
                      titles[i],
                      style: AppText.button.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
              ],
            );
            if (depth != null) model.openLevel(depth);
          },
          child: Text('…', style: AppText.crumb),
        ),
      );
}

/// Where a menu opens under the widget of [context].
RelativeRect _below(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final at = box.localToGlobal(
    Offset(0, box.size.height + 4),
    ancestor: overlay,
  );
  return RelativeRect.fromLTRB(at.dx, at.dy, overlay.size.width - at.dx, 0);
}

/// The chevron of the workflow's crumb: a click lists the workflows to
/// choose from, those of the graph file and then those only sessions ran,
/// marked; the workflow chosen is drawn from its top level.
class _WorkflowPicker extends StatelessWidget {
  const _WorkflowPicker({required this.model});

  final GraphModel model;

  Future<void> _pick(BuildContext context) async {
    final chosen = model.workflow?.id;
    final id = await showMenu<String>(
      context: context,
      color: AppColors.control,
      position: _below(context),
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
  Widget build(BuildContext context) => Tooltip(
    message: 'Choose a workflow',
    child: Clickable(
      key: GraphHeader.workflowKey,
      onTap: () => _pick(context),
      child: const SizedBox.square(
        dimension: _Crumbs._chevron,
        child: Center(
          child: ChevronIcon(size: 12, color: AppColors.textDim, down: true),
        ),
      ),
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
