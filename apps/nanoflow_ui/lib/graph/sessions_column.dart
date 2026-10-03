// migrated in Task 12: still on the old model (runs, the README graph,
// GraphSource); it does not compile until then.
import 'package:flutter/material.dart';

import '../state/clock.dart';
import '../state/graph_model.dart';
import '../state/sessions.dart';
import '../state/texts.dart' show count;
import '../theme.dart';
import '../widgets/clickable.dart';

/// The sessions column (docs/ui-spec.md «Сессии»): `Current graph` on top,
/// then the graph's sessions, newest first, each a card with its status bar;
/// what is selected is highlighted, and a click selects. Without sessions,
/// `No runs yet` and how to start one. A running session's time goes on with
/// the [clock].
class SessionsColumn extends StatelessWidget {
  const SessionsColumn({
    super.key,
    required this.model,
    required this.clock,
    required this.graphFile,
  });

  final GraphModel model;
  final LiveClock clock;

  /// The graph file: the hint without sessions names it.
  final String graphFile;

  /// The key of the card of the session [sessionId].
  static Key cardKey(String sessionId) => ValueKey(('session', sessionId));

  /// The key of the `Current graph` item.
  static const currentGraphKey = ValueKey('current graph');

  /// The key of a card's status bar.
  static const statusBarKey = ValueKey('status bar');

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.panel,
    child: ListenableBuilder(
      listenable: Listenable.merge([model, clock]),
      builder: (context, _) {
        final selection = model.selection;
        final sessions = model.sessions(clock.now());
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: _CurrentGraphItem(
                selected: selection.currentGraph,
                errors: model.source.errors.length,
                onTap: selection.showCurrentGraph,
              ),
            ),
            SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text('Sessions', style: AppText.panelTitle),
                    const Spacer(),
                    Text('${sessions.length}', style: AppText.count),
                  ],
                ),
              ),
            ),
            Expanded(
              child: sessions.isEmpty
                  ? _NoRuns(graphFile)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                      itemCount: sessions.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, i) {
                        final summary = sessions[i];
                        return _SessionCard(
                          key: ValueKey(summary.id),
                          summary: summary,
                          selected:
                              !selection.currentGraph &&
                              selection.sessionId == summary.id,
                          onTap: () => model.showSession(summary.id),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
}

/// A session in the column: the day and time it started and its short id;
/// its status with the time, `1 failed`, and how many runs it has.
class _SessionCard extends StatelessWidget {
  const _SessionCard({
    super.key,
    required this.summary,
    required this.selected,
    required this.onTap,
  });

  final SessionSummary summary;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Item(
    boxKey: SessionsColumn.cardKey(summary.id),
    selected: selected,
    onTap: onTap,
    bar: summary.status.color,
    title: summary.firstLine,
    id: Tooltip(
      message: summary.id,
      child: Text(
        summary.shortId,
        style: AppText.sessionId.copyWith(
          color: selected ? AppColors.accentText : AppColors.textFaint,
        ),
      ),
    ),
    status: summary.statusText,
    statusStyle: AppText.sessionStatus.copyWith(
      color: summary.status.textColor,
    ),
    badge: summary.failedBadge,
    end: Text(summary.runsText, style: AppText.sessionRuns),
  );
}

/// `Current graph`: the graph file as it is now, without a session; how
/// many errors `nanoflow check` finds in it.
class _CurrentGraphItem extends StatelessWidget {
  const _CurrentGraphItem({
    required this.selected,
    required this.errors,
    required this.onTap,
  });

  final bool selected;
  final int errors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Item(
    boxKey: SessionsColumn.currentGraphKey,
    selected: selected,
    onTap: onTap,
    title: 'Current graph',
    status: 'The graph file as it is now',
    statusStyle: AppText.hint,
    badge: errors > 0 ? count(errors, 'error') : null,
  );
}

/// A card of the column, a status [bar] on its left edge, the accent when
/// [selected]: the [title] and the [id] on its first line; the [status],
/// a red [badge] and the [end] on its second. In a narrow column the title
/// and the status give way first.
class _Item extends StatelessWidget {
  const _Item({
    required this.boxKey,
    required this.selected,
    required this.onTap,
    required this.title,
    required this.status,
    required this.statusStyle,
    this.id,
    this.badge,
    this.end,
    this.bar,
  });

  /// The key of the card's box, which tests look at.
  final Key boxKey;

  final bool selected;
  final VoidCallback onTap;
  final String title;
  final Widget? id;
  final String status;
  final TextStyle statusStyle;
  final String? badge;
  final Widget? end;
  final Color? bar;

  /// [lead] taking the room [trail] leaves, on a common baseline.
  static Widget _line(Widget lead, Widget? trail) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    spacing: 8,
    children: [
      Expanded(child: lead),
      ?trail,
    ],
  );

  static Widget _text(String text, TextStyle style) => Text(
    text,
    style: style,
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.ellipsis,
  );

  @override
  Widget build(BuildContext context) => Clickable.hover(
    onTap: onTap,
    builder: (context, hovered) => Container(
      key: boxKey,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: selected
            ? AppColors.accentSurface
            : hovered
            ? AppColors.control
            : AppColors.card,
        border: Border.all(
          color: selected
              ? AppColors.accentBorder
              : hovered
              ? AppColors.controlBorder
              : AppColors.cardBorder,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 4,
              children: [
                _line(_text(title, AppText.sessionTitle), id),
                _line(
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    spacing: 8,
                    children: [
                      Flexible(child: _text(status, statusStyle)),
                      if (badge case final text?) _DangerBadge(text),
                    ],
                  ),
                  end,
                ),
              ],
            ),
          ),
          if (bar case final color?)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 3,
              child: ColoredBox(key: SessionsColumn.statusBarKey, color: color),
            ),
        ],
      ),
    ),
  );
}

/// `1 failed`, `2 errors`: a small red badge.
class _DangerBadge extends StatelessWidget {
  const _DangerBadge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: AppColors.dangerSurface,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: AppText.smallBadge.copyWith(color: AppColors.dangerText),
    ),
  );
}

/// What the column says without sessions.
class _NoRuns extends StatelessWidget {
  const _NoRuns(this.graphFile);

  final String graphFile;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Text(
          noRunsYet,
          style: AppText.sessionTitle.copyWith(color: AppColors.textSecondary),
        ),
        Text(noRunsHint(graphFile), style: AppText.hint),
      ],
    ),
  );
}
