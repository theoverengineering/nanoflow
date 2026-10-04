import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../platform/shell.dart';
import '../../state/effect_details.dart';
import '../../state/effect_files.dart';
import '../../theme.dart';
import '../../widgets/clickable.dart';
import 'document_view.dart';
import 'file_footer.dart';
import 'log_view.dart';

/// A tab of the effect details.
enum EffectTab { output, log }

/// The selected effect's details on the right of the `Logs` panel
/// (docs/ui-spec.md «Logs»: «Детали эффекта»; spec §9 «Окно эффекта»): the
/// effect's name, the tabs `Output` and `Log`, and `Open` for the effect
/// details window. An effect has no input.
///
/// `Output` shows its document as JSON — a failed effect's error instead —
/// `Log` the effect's log; the open tab stays as other effects are selected,
/// `Log` at first. While the log of a running effect holds on to its end,
/// `following tail` says so. With files to point at, the open tab's file is
/// at the bottom.
class EffectDetailsPane extends StatefulWidget {
  const EffectDetailsPane({
    super.key,
    required this.effect,
    required this.files,
    required this.shell,
    required this.graphFile,
    this.onOpenEffect,
  });

  final EffectDetails effect;
  final EffectFiles files;
  final Shell shell;

  /// The graph file: the paths of files are shown from its directory.
  final String graphFile;

  /// Opens the effect details window on the effect.
  final ValueChanged<EffectDetails>? onOpenEffect;

  static Key tabKey(EffectTab tab) => ValueKey(('effect tab', tab));
  static const headerKey = ValueKey('effect details header');
  static const followingKey = ValueKey('following tail');
  static const openKey = ValueKey('open effect');

  @override
  State<EffectDetailsPane> createState() => _EffectDetailsPaneState();
}

class _EffectDetailsPaneState extends State<EffectDetailsPane> {
  EffectTab _tab = EffectTab.log;

  /// Whether the log holds on to its end: anew for each log view, which
  /// opens at the end.
  ValueNotifier<bool> _following = ValueNotifier(true);

  static bool _same(EffectDetails a, EffectDetails b) =>
      a.sessionId == b.sessionId && a.effectId == b.effectId;

  @override
  void didUpdateWidget(EffectDetailsPane old) {
    super.didUpdateWidget(old);
    if (!_same(old.effect, widget.effect)) _followAnew();
  }

  /// A new flag for a new log view: one that holds on. Replaced rather than
  /// set, so that nothing hears of it while the frame is built.
  void _followAnew() {
    final previous = _following;
    // The old log view lets go of it as the next frame is built.
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    _following = ValueNotifier(true);
  }

  void _open(EffectTab tab) => setState(() {
    if (tab == EffectTab.log && _tab != EffectTab.log) _followAnew();
    _tab = tab;
  });

  @override
  void dispose() {
    _following.dispose();
    super.dispose();
  }

  /// The file of the open tab, when there are files.
  String? get _path {
    final effect = widget.effect;
    final files = widget.files;
    return switch (_tab) {
      EffectTab.log => files.logPath(effect.effectId),
      EffectTab.output => switch (effect.output.documentId) {
        final id? => files.documentPath(effect.sessionId, id),
        null => null,
      },
    };
  }

  Widget _body() {
    final effect = widget.effect;
    if (_tab == EffectTab.log) {
      return LogView(
        key: ValueKey(('log', effect.sessionId, effect.effectId)),
        files: widget.files,
        effect: effect,
        following: _following,
      );
    }
    final output = effect.output;
    final id = output.documentId;
    if (id != null) {
      return DocumentView(
        key: ValueKey(('document', effect.sessionId, id)),
        files: widget.files,
        sessionId: effect.sessionId,
        documentId: id,
      );
    }
    return switch (effect.error) {
      final error? => TabNote('Failed: $error', color: AppColors.dangerText),
      null => TabNote(output.message ?? ''),
    };
  }

  @override
  Widget build(BuildContext context) {
    final effect = widget.effect;
    final path = _path;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          effect: effect,
          tab: _tab,
          following: _following,
          onTab: _open,
          onOpen: () => widget.onOpenEffect?.call(effect),
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
    required this.effect,
    required this.tab,
    required this.following,
    required this.onTab,
    required this.onOpen,
  });

  final EffectDetails effect;
  final EffectTab tab;
  final ValueNotifier<bool> following;
  final ValueChanged<EffectTab> onTab;
  final VoidCallback onOpen;

  /// Narrower than this, `following tail` is only its dot.
  static const _roomForBadge = 440.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Container(
      key: EffectDetailsPane.headerKey,
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
                      effect.name,
                      style: AppText.detailsTitle,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                for (final (which, label) in const [
                  (EffectTab.output, 'Output'),
                  (EffectTab.log, 'Log'),
                ])
                  _Tab(
                    which: which,
                    label: label,
                    selected: which == tab,
                    onTap: () => onTab(which),
                  ),
              ],
            ),
          ),
          if (tab == EffectTab.log && effect.running)
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
              label: 'Open effect in details view',
              child: Container(
                key: EffectDetailsPane.openKey,
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

/// A tab: filled when [selected].
class _Tab extends StatelessWidget {
  const _Tab({
    required this.which,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final EffectTab which;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = selected
        ? AppText.tab.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          )
        : AppText.tab.copyWith(color: AppColors.textMuted);
    return Clickable(
      onTap: onTap,
      child: Container(
        key: EffectDetailsPane.tabKey(which),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: selected
            ? BoxDecoration(
                color: AppColors.selectedTab,
                borderRadius: BorderRadius.circular(6),
              )
            : null,
        child: Text(label, style: style, maxLines: 1, softWrap: false),
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
      key: EffectDetailsPane.followingKey,
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
