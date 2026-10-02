import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../platform/home_path.dart';
import '../platform/shell.dart';
import '../state/graph_source.dart';
import '../theme.dart';
import '../widgets/clickable.dart';
import '../widgets/dot.dart';

/// The graph screen's header (docs/ui-spec.md «Экран графа»): `Graphs` back
/// to the start screen, the graph file's name and its directory; on the
/// right the [LiveBadge], `Reveal in Finder` and `Open in editor` for the
/// graph file. When Finder or the editor fails, a note says so for a while.
class GraphHeader extends StatelessWidget {
  const GraphHeader({
    super.key,
    required this.path,
    required this.source,
    required this.shell,
    required this.onBack,
  });

  /// The graph file.
  final String path;

  /// The current graph, for the [LiveBadge].
  final GraphSource source;

  final Shell shell;

  /// Goes back to the start screen.
  final VoidCallback onBack;

  /// How long a note about a failure stays.
  static const _noteTime = Duration(seconds: 3);

  Future<void> _open(
    BuildContext context,
    Future<bool> Function(String path) open,
    String failure,
  ) async {
    if (await open(path) || !context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          failure,
          style: AppText.problemText.copyWith(color: AppColors.dangerText),
        ),
        duration: _noteTime,
        behavior: SnackBarBehavior.floating,
        width: 360,
        backgroundColor: AppColors.dangerSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.dangerBorder),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
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
      child: Row(
        // The mockup's flex gap, round the free space too.
        spacing: 10,
        children: [
          Clickable(
            onTap: onBack,
            child: Text('Graphs', style: AppText.crumb),
          ),
          Text('/', style: AppText.crumbSeparator),
          Text(name, style: AppText.headerTitle),
          Expanded(
            child: Text(
              abbreviateHome(p.dirname(path)),
              style: AppText.headerPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          LiveBadge(source: source),
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
      ),
    );
  }
}

/// Whether what the screen shows is live: `Live · watching runs/`. The
/// `runs` directory is always watched; the current graph is live while its
/// program runs and its file is there, else the badge says which is wrong.
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key, required this.source});

  final GraphSource source;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: source,
    builder: (context, _) {
      final problem = source.programProblem;
      final (state, dot, fill, border, text) = source.fileMissing
          ? (
              fileUnavailable,
              AppColors.failed,
              AppColors.dangerSurface,
              AppColors.dangerBorder,
              AppColors.dangerText,
            )
          : problem != null
          ? (
              'Graph not live',
              AppColors.running,
              AppColors.runningSurface,
              AppColors.runningBorder,
              AppColors.running,
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
      return problem == null || source.fileMissing
          ? badge
          : Tooltip(message: problem.message, child: badge);
    },
  );
}

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
