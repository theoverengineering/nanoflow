import 'package:flutter/material.dart';

import '../state/clock.dart';
import '../state/freshness.dart' show CodeCheck;
import '../state/graph_model.dart';
import '../state/sessions.dart';
import '../theme.dart';
import '../widgets/clickable.dart';

/// The sessions column (docs/ui-spec.md «Сессии»): `Current graph` on top,
/// then the graph's sessions, newest first, each a card with its status bar;
/// what is selected is highlighted, and a click selects. Without sessions,
/// `No sessions yet` and where they come from. A running session's time goes on with
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
                  ? _NoSessions(graphFile)
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
/// its status with the time — `Interrupted`, why in a tooltip, when its
/// process is gone — `1 failed`, and how many steps it has; `other code` or
/// `not checked` when its code is not its graph's, and `Log read
/// incompletely` when its journal was, why in a tooltip.
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
    bar: summary.statusColor,
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
    statusWhy: summary.statusWhy,
    statusStyle: AppText.sessionStatus.copyWith(color: summary.statusTextColor),
    badge: summary.failedBadge,
    note: summary.codeNote,
    noteMuted: summary.code == CodeCheck.notChecked,
    resumedNote: summary.resumedNote,
    incompleteWhy: summary.incompleteWhy,
    end: Text(summary.stepsText, style: AppText.sessionSteps),
  );
}

/// `Current graph`: the graph file as it is now, without a session.
class _CurrentGraphItem extends StatelessWidget {
  const _CurrentGraphItem({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Item(
    boxKey: SessionsColumn.currentGraphKey,
    selected: selected,
    onTap: onTap,
    title: 'Current graph',
    status: 'The graph file as it is now',
    statusStyle: AppText.hint,
  );
}

/// A card of the column, a status [bar] on its left edge, the accent when
/// [selected]: the [title] and the [id] on its first line; the [status],
/// [statusWhy] in its tooltip, a red [badge] and the [end] on its second;
/// an amber [note] — muted when [noteMuted] — the amber [resumedNote] and
/// the `Log read incompletely` mark, [incompleteWhy] in its tooltip, on a
/// line of their own, so that the status keeps its room; a mark goes under
/// the one before when the line is too narrow for both. In a narrow column
/// the title and the status give way first.
class _Item extends StatelessWidget {
  const _Item({
    required this.boxKey,
    required this.selected,
    required this.onTap,
    required this.title,
    required this.status,
    required this.statusStyle,
    this.statusWhy,
    this.id,
    this.badge,
    this.note,
    this.noteMuted = false,
    this.resumedNote,
    this.incompleteWhy,
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
  final String? statusWhy;
  final String? badge;
  final String? note;
  final bool noteMuted;
  final String? resumedNote;
  final String? incompleteWhy;
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
                      Flexible(
                        child: switch (statusWhy) {
                          final why? => Tooltip(
                            message: why,
                            child: _text(status, statusStyle),
                          ),
                          null => _text(status, statusStyle),
                        },
                      ),
                      if (badge case final text?) _DangerBadge(text),
                    ],
                  ),
                  end,
                ),
                if (note != null ||
                    resumedNote != null ||
                    incompleteWhy != null)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (note case final text?)
                        _NoteBadge(text, muted: noteMuted),
                      if (resumedNote case final text?)
                        _NoteBadge(text, muted: false),
                      if (incompleteWhy case final why?)
                        Tooltip(message: why, child: const _IncompleteBadge()),
                    ],
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

/// `other code`, `resumed on changed code`: a small amber badge;
/// `not checked` muted.
class _NoteBadge extends StatelessWidget {
  const _NoteBadge(this.text, {required this.muted});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: muted ? AppColors.selectedTab : AppColors.noteSurface,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: AppText.smallBadge.copyWith(
        color: muted ? AppColors.textMuted : AppColors.noteText,
      ),
    ),
  );
}

/// `Log read incompletely`: a small amber badge with a warning sign.
class _IncompleteBadge extends StatelessWidget {
  const _IncompleteBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: AppColors.noteSurface,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        CustomPaint(size: const Size.square(10), painter: _WarningPainter()),
        Text(
          logReadIncompletely,
          style: AppText.smallBadge.copyWith(color: AppColors.noteText),
        ),
      ],
    ),
  );
}

/// A triangle with `!` in it, in the note's amber.
class _WarningPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 12);
    final stroke = Paint()
      ..color = AppColors.noteText
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(
        Path()
          ..moveTo(6, 1.5)
          ..lineTo(11, 10.5)
          ..lineTo(1, 10.5)
          ..close(),
        stroke,
      )
      ..drawLine(const Offset(6, 5), const Offset(6, 7.2), stroke)
      ..drawCircle(
        const Offset(6, 9),
        0.75,
        Paint()..color = AppColors.noteText,
      );
  }

  @override
  bool shouldRepaint(_WarningPainter old) => false;
}

/// What the column says without sessions.
class _NoSessions extends StatelessWidget {
  const _NoSessions(this.graphFile);

  final String graphFile;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Text(
          noSessionsYet,
          style: AppText.sessionTitle.copyWith(color: AppColors.textSecondary),
        ),
        Text(noSessionsHint(graphFile), style: AppText.hint),
      ],
    ),
  );
}
