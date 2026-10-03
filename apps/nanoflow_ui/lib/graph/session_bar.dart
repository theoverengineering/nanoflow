import 'package:flutter/material.dart';

import '../state/clock.dart';
import '../state/graph_model.dart';
import '../state/sessions.dart';
import '../state/texts.dart' show shortId;
import '../theme.dart';
import '../widgets/dot.dart';

/// The session bar floating over the top of the canvas (docs/ui-spec.md
/// «Холст»): `Session a1b2 · started 14:03:11 · ● running 12m 26s`, whose
/// time goes on with the [clock] — `interrupted after 3m 20s`, why in a
/// tooltip, once its process is gone; then `resumed on changed code` for a
/// session resumed on other code than it started on. The canvas moves under
/// it; it stays. With `Current graph` selected there is no session, and no
/// bar.
class SessionBar extends StatelessWidget {
  const SessionBar({super.key, required this.model, required this.clock});

  final GraphModel model;
  final LiveClock clock;

  /// How tall the bar is, when there is one.
  static const height = 36.0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([model, clock]),
    builder: (context, _) {
      final session = model.selectedSession;
      final view = model.sessionView(clock.now());
      if (session == null || view == null) return const SizedBox.shrink();
      return SizedBox(
        height: height,
        child: Align(
          alignment: Alignment.centerLeft,
          child: _Session(id: session.id, summary: view.summary),
        ),
      );
    },
  );
}

/// The session's short id (the full one in a tooltip), when it started, how
/// it is, and whether it was resumed on changed code; only the id before it
/// has started. Short of room, the status and that mark give way.
class _Session extends StatelessWidget {
  const _Session({required this.id, required this.summary});

  final String id;
  final SessionSummary? summary;

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    final separator = Text('·', style: AppText.barSeparator);
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.panelBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 9,
        children: [
          Text('Session', style: AppText.barLabel),
          Tooltip(
            message: id,
            child: Text(shortId(id), style: AppText.barId),
          ),
          if (summary != null) ...[
            separator,
            Text(summary.startedText, style: AppText.barLabel),
            separator,
            Flexible(child: _status(summary)),
            if (summary.resumedNote case final mark?) ...[
              separator,
              Flexible(
                child: Text(
                  mark,
                  style: AppText.barLabel.copyWith(color: AppColors.noteText),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// `● running 12m 26s`; why it is, in a tooltip, when the summary says.
  static Widget _status(SessionSummary summary) {
    final status = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        Dot(summary.statusColor),
        Flexible(
          child: Text(
            summary.stripStatus,
            style: AppText.barLabel.copyWith(color: summary.statusTextColor),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    return switch (summary.statusWhy) {
      final why? => Tooltip(message: why, child: status),
      null => status,
    };
  }
}
