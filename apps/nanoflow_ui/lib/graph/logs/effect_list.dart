import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nanoflow_model/nanoflow_model.dart' show SessionStatus;

import '../../state/log_rows.dart';
import '../../state/texts.dart' show count;
import '../../state/visits.dart' show StartOutcome;
import '../../theme.dart';
import '../../widgets/clickable.dart';
import 'effect_bar.dart';

/// The effects shown on the left of the `Logs` panel (docs/ui-spec.md «Logs»:
/// «Лента эффектов»; spec §9 «Логи»), as the rows of `logRows` give them: each
/// effect's sign, name, a failure's error or `not on the graph`, the copy it
/// is in while every copy is shown, `2 starts`, when it started, how long it
/// took — a running one's time going on — and its bar on the session's time
/// scale, striped while it runs. An ended session ends with how it ended.
///
/// The selected effect is highlighted, and kept in view as the selection
/// moves; while the session is followed, so are the rows after it. Scrolled
/// down, the list says how many effects are above it.
class EffectList extends StatefulWidget {
  const EffectList({
    super.key,
    required this.rows,
    required this.scale,
    required this.selectedEffectId,
    required this.following,
    required this.onSelect,
  });

  final List<LogRow> rows;

  /// The time scale of the rows' bars, for the axis.
  final TimeScale scale;

  final String? selectedEffectId;

  /// Whether the selection moves on to each new effect of the session.
  final bool following;

  /// A click on an effect's row.
  final ValueChanged<EffectRow> onSelect;

  static Key rowKey(String effectId) => ValueKey(('effect row', effectId));
  static const endKey = ValueKey('end row');
  static const earlierKey = ValueKey('earlier effects');

  @override
  State<EffectList> createState() => _EffectListState();
}

/// The mockups' sizes.
abstract final class _Sizes {
  static const header = 24.0;
  static const row = 22.0;
  static const selected = 24.0;
  static const earlier = 20.0;
  static const padding = 16.0;
  static const gap = 10.0;
  static const sign = EffectIcon.size;
  static const started = 58.0;
  static const took = 50.0;
  static const timeline = 150.0;

  /// The least room the effect's name keeps before the timeline gives way.
  static const name = 100.0;

  /// Narrower than this, there is no timeline.
  static const leastTimeline = 40.0;
}

class _EffectListState extends State<EffectList> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _keepInView();
  }

  @override
  void didUpdateWidget(EffectList old) {
    super.didUpdateWidget(old);
    if (old.selectedEffectId != widget.selectedEffectId ||
        widget.following && old.rows.length != widget.rows.length) {
      _keepInView();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double _extentOf(LogRow row) => switch (row) {
    EffectRow(:final effectId) =>
      effectId == widget.selectedEffectId ? _Sizes.selected : _Sizes.row,
    EndRow() => _Sizes.row,
  };

  /// Scrolls the selected row into view once laid out, and while
  /// following, the rows after it too; clear of the note on top.
  void _keepInView() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || !_scroll.hasClients) return;
    final rows = widget.rows;
    var top = 0.0;
    double? start;
    double? end;
    for (final row in rows) {
      final extent = _extentOf(row);
      if (row is EffectRow && row.effectId == widget.selectedEffectId) {
        start = top;
        end = top + extent;
      }
      top += extent;
    }
    if (start == null || end == null) return;
    final position = _scroll.position;
    final view = position.viewportDimension;
    if (widget.following) end = math.min(top, start + view);
    var offset = position.pixels;
    if (end > offset + view) offset = end - view;
    final cover = offset > 0 ? _Sizes.earlier : 0.0;
    if (start < offset + cover) {
      offset = start <= 0 ? 0 : start - _Sizes.earlier;
    }
    offset = offset.clamp(0.0, position.maxScrollExtent);
    if (offset != position.pixels) _scroll.jumpTo(offset);
  });

  /// How many effects are scrolled away above, or under the note on top.
  int _earlier() {
    if (!_scroll.hasClients || _scroll.offset <= 0) return 0;
    final hidden = _scroll.offset + _Sizes.earlier;
    var top = 0.0;
    var count = 0;
    for (final row in widget.rows) {
      top += _extentOf(row);
      if (top > hidden) break;
      if (row is EffectRow) count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final room =
          constraints.maxWidth -
          2 * _Sizes.padding -
          _Sizes.sign -
          _Sizes.started -
          _Sizes.took -
          4 * _Sizes.gap -
          _Sizes.name;
      final timeline = math.min(_Sizes.timeline, room);
      final columns = _Columns(
        timeline: timeline >= _Sizes.leastTimeline ? timeline : null,
      );
      final rows = widget.rows;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ColumnTitles(columns, axis: widget.scale.axis),
          Expanded(
            child: Stack(
              children: [
                ListView.builder(
                  controller: _scroll,
                  itemCount: rows.length,
                  itemExtentBuilder: (i, _) =>
                      i < rows.length ? _extentOf(rows[i]) : null,
                  itemBuilder: (context, i) => switch (rows[i]) {
                    final EffectRow row => _EffectRowView(
                      row,
                      columns: columns,
                      selected: row.effectId == widget.selectedEffectId,
                      onTap: () => widget.onSelect(row),
                    ),
                    final EndRow row => _EndRowView(row, columns: columns),
                  },
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  child: ListenableBuilder(
                    listenable: _scroll,
                    builder: (context, _) => switch (_earlier()) {
                      0 => const SizedBox.shrink(),
                      final count => _EarlierNote(
                        count,
                        onTap: () => _scroll.animateTo(
                          0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                        ),
                      ),
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

/// The widths of the columns after the effect's: the timeline's, `null`
/// without room for it.
final class _Columns {
  const _Columns({required this.timeline});

  final double? timeline;

  /// [sign], [effect] (taking the room left), [started], [took] and [bar] in a
  /// row, as the mockup's flex row with its gaps and padding has them.
  Widget row({
    required Widget sign,
    required Widget effect,
    required Widget started,
    required Widget took,
    Widget? bar,
  }) {
    final timeline = this.timeline;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _Sizes.padding),
      child: Row(
        spacing: _Sizes.gap,
        children: [
          SizedBox(
            width: _Sizes.sign,
            child: Center(child: sign),
          ),
          Expanded(child: effect),
          SizedBox(width: _Sizes.started, child: started),
          SizedBox(width: _Sizes.took, child: took),
          if (timeline != null) SizedBox(width: timeline, child: bar),
        ],
      ),
    );
  }
}

/// `Effect`, `Started`, `Took`, and the timeline's axis: `0m 6m 12m`.
class _ColumnTitles extends StatelessWidget {
  const _ColumnTitles(this.columns, {required this.axis});

  final _Columns columns;
  final List<String> axis;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _Sizes.header,
    child: columns.row(
      sign: const SizedBox.shrink(),
      effect: Text('Effect', style: AppText.columnTitle),
      started: Text('Started', style: AppText.columnTitle),
      took: Text(
        'Took',
        style: AppText.columnTitle,
        textAlign: TextAlign.right,
      ),
      bar: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final label in axis) Text(label, style: AppText.axisLabel),
        ],
      ),
    ),
  );
}

/// An effect's row.
class _EffectRowView extends StatelessWidget {
  const _EffectRowView(
    this.row, {
    required this.columns,
    required this.selected,
    required this.onTap,
  });

  final EffectRow row;
  final _Columns columns;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final running = row.status == StartOutcome.running;
    final detail = row.detail;
    final starts = row.startsText;
    final copy = row.copy;
    final effect = Text.rich(
      TextSpan(
        text: row.name,
        style: selected
            ? AppText.effectName.copyWith(
                color: AppColors.selectedText,
                fontWeight: FontWeight.w600,
              )
            : AppText.effectName,
        children: [
          if (detail != null) ...[
            const TextSpan(text: ' '),
            TextSpan(
              text: detail,
              style: row.failure
                  ? AppText.effectDetail.copyWith(color: AppColors.dangerText)
                  : AppText.effectDetail,
            ),
          ],
        ],
      ),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
    final content = columns.row(
      sign: EffectIcon(row.status),
      effect: Row(
        // The width of a space between the name and the note.
        spacing: 3,
        children: [
          Flexible(
            child: detail == null
                ? effect
                : Tooltip(message: detail, child: effect),
          ),
          if (copy != null) _CopyNote(copy),
          if (starts != null) _StartsNote(starts),
        ],
      ),
      started: Text(
        row.started,
        style: selected
            ? AppText.effectTime.copyWith(color: AppColors.accentText)
            : AppText.effectTime,
      ),
      took: Text(
        row.took,
        textAlign: TextAlign.right,
        style: running
            ? AppText.effectTook.copyWith(
                color: AppColors.running,
                fontWeight: FontWeight.w500,
              )
            : AppText.effectTook,
      ),
      bar: EffectTrack(row),
    );
    return Clickable(
      onTap: onTap,
      child: Container(
        key: EffectList.rowKey(row.effectId),
        decoration: selected
            ? const BoxDecoration(color: AppColors.accentSurface)
            : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            if (selected)
              const Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: ColoredBox(color: AppColors.accentLine),
              ),
          ],
        ),
      ),
    );
  }
}

/// `2 starts`: an amber note.
class _StartsNote extends StatelessWidget {
  const _StartsNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      color: AppColors.noteSurface,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: AppText.startsNote),
  );
}

/// `pkg 2`, `pkg 2 › target 1`: the copies an effect is in.
class _CopyNote extends StatelessWidget {
  const _CopyNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      color: AppColors.selectedTab,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: AppText.startsNote.copyWith(color: AppColors.textMuted),
    ),
  );
}

/// How the session ended: `Session finished`, `Session failed: StateError:
/// plan failed`; and when.
class _EndRowView extends StatelessWidget {
  const _EndRowView(this.row, {required this.columns});

  final EndRow row;
  final _Columns columns;

  @override
  Widget build(BuildContext context) {
    final failed = row.status == SessionStatus.failed;
    final text = Text(
      row.text,
      style: AppText.listNote.copyWith(color: row.status.textColor),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
    return KeyedSubtree(
      key: EffectList.endKey,
      child: columns.row(
        sign: EffectIcon(failed ? StartOutcome.failed : StartOutcome.finished),
        effect: failed ? Tooltip(message: row.text, child: text) : text,
        started: Text(row.atText, style: AppText.effectTime),
        took: const SizedBox.shrink(),
      ),
    );
  }
}

/// `↑ 8 earlier effects` over the top of the list; a click scrolls up.
class _EarlierNote extends StatelessWidget {
  const _EarlierNote(this.effects, {required this.onTap});

  final int effects;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Clickable(
    onTap: onTap,
    child: Container(
      key: EffectList.earlierKey,
      height: _Sizes.earlier,
      color: AppColors.panel,
      padding: const EdgeInsets.only(left: 40),
      alignment: Alignment.centerLeft,
      child: Text(
        '↑ ${count(effects, 'earlier effect')}',
        style: AppText.listNote.copyWith(color: AppColors.textFaint),
      ),
    ),
  );
}
